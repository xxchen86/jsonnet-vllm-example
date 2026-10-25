// 外部变量（ext vars）演示：把运行时的值注入到配置里
// 运行：
//   jsonnet -J . -e "std.extVar('region')" --ext-str region=cn-north-1
//   jsonnet examples/ext-vars.jsonnet --ext-str region=cn-north-1 --ext-str tag=v2 --ext-code debug=false
local region = std.extVar('region');
local tag = std.extVar('tag');
local debug = std.extVar('debug');  // --ext-code 可以传真正的布尔/数字/数组

{
  region: region,
  image: 'demo/api:' + tag,
  debug: debug,
  replicas: if debug then 1 else 3,
}
