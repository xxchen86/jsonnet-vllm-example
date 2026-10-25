// 09 · 实战：参数化模板 + mixin 组合出 Kubernetes 多文档清单
// JSON：     jsonnet examples/capabilities/09-k8s.jsonnet
// YAML 流：  jsonnet -y examples/capabilities/09-k8s.jsonnet

local env = 'prod';
local app = 'demo-api';
local imageTag = if env == 'prod' then '1.4.0' else 'dev';

local container = {
  name: app,
  image: 'registry.example.com/%s:%s' % [app, imageTag],
  ports: [{ name: 'http', containerPort: 8080 }],
  envFrom: [{ configMapRef: { name: app + '-config' } }],
  resources: {
    requests: { cpu: '100m', memory: '128Mi' },
    limits: { cpu: '500m', memory: '512Mi' },
  },
  readinessProbe: {
    httpGet: { path: '/healthz', port: 'http' },
    initialDelaySeconds: 3,
  },
};

// 混入：给任意工作负载追加一个 sidecar 容器
local withSidecar(sidecar) = {
  spec+: {
    template+: {
      spec+: {
        containers+: [sidecar],
      },
    },
  },
};

local deployment =
  {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: app,
      namespace: env,
      labels: { app: app },
    },
    spec: {
      replicas: if env == 'prod' then 5 else 1,
      selector: { matchLabels: { app: app } },
      template: {
        metadata: { labels: { app: app } },
        spec: {
          containers: [container],
        },
      },
    },
  }
  + withSidecar({
    name: 'log-shipper',
    image: 'registry.example.com/log-shipper:2.1.0',
    args: ['--source=/var/log/app.log'],
  });

local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: { name: app, namespace: env },
  spec: {
    selector: { app: app },
    ports: [{ name: 'http', port: 80, targetPort: 'http' }],
  },
};

local configMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: app + '-config', namespace: env },
  data: {
    LOG_LEVEL: if env == 'prod' then 'warn' else 'debug',
    APP_ENV: env,
  },
};

// 顶层数组配合 -y 输出多文档 YAML
[configMap, deployment, service]
