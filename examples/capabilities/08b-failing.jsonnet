// 08b · 故意失败：演示断言错误信息与退出码
// 运行：jsonnet examples/capabilities/08b-failing.jsonnet
// 预期：退出码 1，stderr 包含 "replicas 必须 >= 1"

local replicas = 0;

assert replicas >= 1 : 'replicas 必须 >= 1';

{
  replicas: replicas,
}
