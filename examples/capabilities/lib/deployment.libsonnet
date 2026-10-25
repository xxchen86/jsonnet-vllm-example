// 可复用模块：文件求值结果是一个函数（参数化模板）
local labels(name) = { app: name };

function(name, port) {
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: name,
    labels: labels(name),
  },
  spec: {
    replicas: 1,
    selector: { matchLabels: labels(name) },
    template: {
      metadata: { labels: labels(name) },
      spec: {
        containers: [{
          name: name,
          image: 'registry.example.com/%s:latest' % name,
          ports: [{ containerPort: port }],
        }],
      },
    },
  },
}
