// 03 · 继承与组合：字段合并、super、self、mixin、+:
// 运行：jsonnet examples/capabilities/03-inheritance.jsonnet

local base = {
  name: 'app',
  replicas: 2,
  labels: { app: 'app' },
  ports: [80],
  _internal:: 'base-only',
  secret:: 'hidden',
};

// 可复用的 mixin：只声明差异，通过 + 叠加
local withMetrics = {
  ports+: [9100],  // 与 super.ports 拼接
  labels+: { metrics: 'true' },  // 在父值基础上合并
  metrics: true,
};

// 参数化 mixin：函数返回对象，再参与合并
local withResources(cpu, memory) = {
  resources: {
    requests: { cpu: cpu, memory: memory },
  },
};

local prod =
  base + withMetrics + withResources('500m', '512Mi') {
    replicas: 5,
    // super 读取被覆盖前的值
    baseReplicas: super.replicas,
    // self 是晚绑定的，指向最终的 prod 对象
    summary: '%s x%d ports=%s' % [
      self.name,
      self.replicas,
      std.join(',', [std.toString(p) for p in self.ports]),
    ],
    // ::: 覆盖父对象的隐藏字段，并强制它出现在输出中
    secret::: 'now-visible',
  };

{
  prod: prod,
  hasHiddenInternal: std.objectHasAll(prod, '_internal'),
  ports: prod.ports,
  labels: prod.labels,
  baseReplicas: prod.baseReplicas,
  summary: prod.summary,
}
