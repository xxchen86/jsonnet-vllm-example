// 06d · 静态 import + -J 选择配置目录（不依赖 extVar/TLA）
//
// 目录中准备同一相对路径的 params.json：
//   params/dev/params.json
//   params/prod/params.json
//
// 运行：
//   jsonnet -J examples/capabilities/params/prod examples/capabilities/06d-import-params.jsonnet
//   jsonnet -J examples/capabilities/params/dev  examples/capabilities/06d-import-params.jsonnet
//
// 注意：import 路径必须是字符串字面量，不能在运行时用变量拼路径。

local params = import 'params.json';

{
  app: params.app,
  environment: params.env,
  region: std.get(params, 'region', 'cn-north-1'),
  replicas: std.get(params, 'replicas', 1),
  image: 'registry.example.com/%s:%s' % [params.app, std.get(params, 'tag', 'latest')],
  features: std.get(params, 'features', {}),
}
