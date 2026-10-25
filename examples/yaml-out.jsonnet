// 多文档 YAML 输出演示：
//   jsonnet -y examples/yaml-out.jsonnet      （等价于 --yaml-stream）
//   jsonnet -S examples/yaml-out.jsonnet      （单文档 YAML，--string）
[
  { kind: 'Namespace', metadata: { name: 'demo' } },
  { kind: 'ConfigMap', metadata: { name: 'demo-config' }, data: { region: 'cn-north-1' } },
]
