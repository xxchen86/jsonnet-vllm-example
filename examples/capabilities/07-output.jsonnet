// 07 · 输出形态：默认 JSON、YAML/JSON 字符串渲染
// 默认 JSON：  jsonnet examples/capabilities/07-output.jsonnet
// 单文档 YAML（-S 要求顶层是字符串）：
//   jsonnet -S -e "std.manifestYamlDoc({ hello: 'world' })"
// 多文档 YAML 流（-y 要求顶层是数组）见 09-k8s.jsonnet

{
  app: 'demo',
  replicas: 3,
  features: { newUI: true },

  // 在配置内部生成 YAML / JSON 字符串，方便嵌入 ConfigMap 等字段
  renderedYaml: std.manifestYamlDoc({ app: 'demo', replicas: 3 }),
  renderedJson: std.manifestJsonEx({ app: 'demo', replicas: 3 }, '  '),
}
