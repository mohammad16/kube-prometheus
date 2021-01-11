local kubeRbacProxyContainer = import './kube-rbac-proxy/containerMixin.libsonnet';

local alertmanager = import './alertmanager/alertmanager.libsonnet';
local blackboxExporter = import './blackbox-exporter/blackbox-exporter.libsonnet';
local kubeStateMetrics = import './kube-state-metrics/kube-state-metrics.libsonnet';
local nodeExporter = import './node-exporter/node-exporter.libsonnet';
local prometheusAdapter = import './prometheus-adapter/prometheus-adapter.libsonnet';

local mixins = import './mixins/monitoring-mixins.libsonnet';

(import 'github.com/brancz/kubernetes-grafana/grafana/grafana.libsonnet') +
(import 'github.com/prometheus-operator/prometheus-operator/jsonnet/prometheus-operator/prometheus-operator.libsonnet') +
(import './prometheus/prometheus.libsonnet') +

{
  alertmanager: alertmanager({
    name: 'main',
    namespace: $._config.namespace,
    version: '0.21.0',
    image: 'quay.io/prometheus/alertmanager:v0.21.0',
  }),
  blackboxExporter: blackboxExporter({
    namespace: $._config.namespace,
    version: '0.18.0',
    image: 'quay.io/prometheus/blackbox-exporter:v0.18.0',
  }),
  kubeStateMetrics: kubeStateMetrics({
    namespace: $._config.namespace,
    version: '1.9.7',
    image: 'quay.io/coreos/kube-state-metrics:v1.9.7',
  }),
  nodeExporter: nodeExporter({
    namespace: $._config.namespace,
    version: '1.0.1',
    image: 'quay.io/prometheus/node-exporter:v1.0.1',
  }),
  prometheusAdapter: prometheusAdapter({
    namespace: $._config.namespace,
    version: '0.8.2',
    image: 'directxman12/k8s-prometheus-adapter:v0.8.2',
    prometheusURL: 'http://prometheus-' + $._config.prometheus.name + '.' + $._config.namespace + '.svc.cluster.local:9090/',
  }),
  kubePrometheus+:: {
    namespace: {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: $._config.namespace,
      },
    },
  },
  prometheusOperator+::
    {
      service+: {
        spec+: {
          ports: [
            {
              name: 'https',
              port: 8443,
              targetPort: 'https',
            },
          ],
        },
      },
      serviceMonitor+: {
        spec+: {
          endpoints: [
            {
              port: 'https',
              scheme: 'https',
              honorLabels: true,
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              tlsConfig: {
                insecureSkipVerify: true,
              },
            },
          ],
        },
      },
      clusterRole+: {
        rules+: [
          {
            apiGroups: ['authentication.k8s.io'],
            resources: ['tokenreviews'],
            verbs: ['create'],
          },
          {
            apiGroups: ['authorization.k8s.io'],
            resources: ['subjectaccessreviews'],
            verbs: ['create'],
          },
        ],
      },
    } +
    (kubeRbacProxyContainer {
       config+:: {
         kubeRbacProxy: {
           image: $._config.imageRepos.kubeRbacProxy + ':' + $._config.versions.kubeRbacProxy,
           name: 'kube-rbac-proxy',
           securePortName: 'https',
           securePort: 8443,
           secureListenAddress: ':%d' % self.securePort,
           upstream: 'http://127.0.0.1:8080/',
           tlsCipherSuites: $._config.tlsCipherSuites,
         },
       },
     }).deploymentMixin,

  grafana+:: {
    local dashboardDefinitions = super.dashboardDefinitions,

    dashboardDefinitions: {
      apiVersion: 'v1',
      kind: 'ConfigMapList',
      items: dashboardDefinitions,
    },
    serviceMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'grafana',
        namespace: $._config.namespace,
        labels: $._config.grafana.labels,
      },
      spec: {
        selector: {
          matchLabels: {
            app: 'grafana',
          },
        },
        endpoints: [{
          port: 'http',
          interval: '15s',
        }],
      },
    },
  },
} + {
  _config+:: {
    namespace: 'default',

    versions+:: { grafana: '7.3.5', kubeRbacProxy: 'v0.8.0' },
    imageRepos+:: { kubeRbacProxy: 'quay.io/brancz/kube-rbac-proxy' },

    tlsCipherSuites: [
      'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',  // required by h2: http://golang.org/cl/30721
      'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',  // required by h2: http://golang.org/cl/30721

      // 'TLS_RSA_WITH_RC4_128_SHA',                // insecure: https://access.redhat.com/security/cve/cve-2013-2566
      // 'TLS_RSA_WITH_3DES_EDE_CBC_SHA',           // insecure: https://access.redhat.com/articles/2548661
      // 'TLS_RSA_WITH_AES_128_CBC_SHA',            // disabled by h2
      // 'TLS_RSA_WITH_AES_256_CBC_SHA',            // disabled by h2
      // 'TLS_RSA_WITH_AES_128_CBC_SHA256',         // insecure: https://access.redhat.com/security/cve/cve-2013-0169
      // 'TLS_RSA_WITH_AES_128_GCM_SHA256',         // disabled by h2
      // 'TLS_RSA_WITH_AES_256_GCM_SHA384',         // disabled by h2
      // 'TLS_ECDHE_ECDSA_WITH_RC4_128_SHA',        // insecure: https://access.redhat.com/security/cve/cve-2013-2566
      // 'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA',    // disabled by h2
      // 'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA',    // disabled by h2
      // 'TLS_ECDHE_RSA_WITH_RC4_128_SHA',          // insecure: https://access.redhat.com/security/cve/cve-2013-2566
      // 'TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA',     // insecure: https://access.redhat.com/articles/2548661
      // 'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA',      // disabled by h2
      // 'TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA',      // disabled by h2
      // 'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256', // insecure: https://access.redhat.com/security/cve/cve-2013-0169
      // 'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256',   // insecure: https://access.redhat.com/security/cve/cve-2013-0169

      // disabled by h2 means: https://github.com/golang/net/blob/e514e69ffb8bc3c76a71ae40de0118d794855992/http2/ciphers.go

      'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
      'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384',
      'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305',
      'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305',
    ],

    resources+:: {
      'addon-resizer': {
        requests: { cpu: '10m', memory: '30Mi' },
        limits: { cpu: '50m', memory: '30Mi' },
      },
      'kube-rbac-proxy': {
        requests: { cpu: '10m', memory: '20Mi' },
        limits: { cpu: '20m', memory: '40Mi' },
      },
    },
    
    local allRules =
      mixins.mixins.nodeExporter.prometheusRules +
      mixins.mixins.kubernetes.prometheusRules +
      mixins.mixins.base.prometheusRules +
      mixins.mixins.kubeStateMetrics.prometheusAlerts +
      mixins.mixins.nodeExporter.prometheusAlerts +
      mixins.mixins.alertmanager.prometheusAlerts +
      mixins.mixins.prometheusOperator.prometheusAlerts +
      mixins.mixins.kubernetes.prometheusAlerts +
      mixins.mixins.prometheus.prometheusAlerts +
      mixins.mixins.base.prometheusAlerts,

    local allDashboards =
      mixins.mixins.nodeExporter.grafanaDashboards +
      mixins.mixins.kubernetes.grafanaDashboards +
      mixins.mixins.prometheus.grafanaDashboards,

    prometheus+:: { rules: allRules },
    grafana+:: {
      labels: {
        'app.kubernetes.io/name': 'grafana',
        'app.kubernetes.io/version': $._config.versions.grafana,
        'app.kubernetes.io/component': 'grafana',
        'app.kubernetes.io/part-of': 'kube-prometheus',
      },
      dashboards: allDashboards,
    },
  },
}
