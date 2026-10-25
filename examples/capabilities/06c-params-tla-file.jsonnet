// 06c · 用一个外部 JSON 文件作为 TLA（顶层函数参数）
//
// 运行：
//   jsonnet examples/capabilities/06c-params-tla-file.jsonnet --tla-code-file params=examples/capabilities/params/prod/params.json
//   jsonnet examples/capabilities/06c-params-tla-file.jsonnet --tla-code-file params=examples/capabilities/params/dev/params.json
//
// 相比 extVar，TLA 把依赖显式写在入口函数上，复用和测试更清晰。

function(params) {
  app: params.app,
  environment: params.env,
  region: std.get(params, 'region', 'cn-north-1'),
  replicas: std.get(params, 'replicas', 1),
  image: 'registry.example.com/%s:%s' % [params.app, std.get(params, 'tag', 'latest')],
  features: std.get(params, 'features', {}),
}
