// 06 · 外部参数：extVar（全局注入）与 TLA（顶层函数参数）
//
// 传 TLA，覆盖函数默认值：
//   jsonnet examples/capabilities/06-extvar-tla.jsonnet --ext-str env=prod --ext-code replicas=3 --tla-str app=api --tla-code canary=true
// 不传 TLA，使用默认参数（extVar 仍然必须提供）：
//   jsonnet examples/capabilities/06-extvar-tla.jsonnet --ext-str env=dev --ext-code replicas=1

local env = std.extVar('env');
local replicas = std.extVar('replicas');  // --ext-code 可注入数字/布尔/数组/对象

function(app='api', canary=false) {
  app: app,
  environment: env,
  replicas: replicas,
  canary: canary,
  image: 'registry.example.com/%s:%s' % [
    app,
    if env == 'prod' then '1.4.0' else 'dev',
  ],
  strategy: if canary then 'canary' else 'rolling',
}
