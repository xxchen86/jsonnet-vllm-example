// 06b · 用一个外部 JSON 文件作为 extVar
//
// 运行：
//   jsonnet examples/capabilities/06b-params-file.jsonnet --ext-code-file params=examples/capabilities/params/prod/params.json
//   jsonnet examples/capabilities/06b-params-file.jsonnet --ext-code-file params=examples/capabilities/params/dev/params.json
//
// --ext-code-file 会把文件内容当作 Jsonnet 代码求值；JSON 是合法的 Jsonnet 子集。
// 如果参数文件是不可信数据，改用 --ext-str-file + std.parseJson，避免执行代码。

local params = std.extVar('params');

// 必填字段校验
assert std.objectHasAll(params, 'app') : 'params.app is required';
assert std.objectHasAll(params, 'env') : 'params.env is required';

{
  app: params.app,
  environment: params.env,
  region: std.get(params, 'region', 'cn-north-1'),
  replicas: std.get(params, 'replicas', 1),
  image: 'registry.example.com/%s:%s' % [params.app, std.get(params, 'tag', 'latest')],
  features: std.get(params, 'features', {}),
  debug: std.get(std.get(params, 'features', {}), 'debug', false),
}
