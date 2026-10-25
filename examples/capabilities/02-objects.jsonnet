// 02 · 对象模型：字段、隐藏字段、self、$、方法、对象推导
// 运行：jsonnet examples/capabilities/02-objects.jsonnet

local serviceName = 'api';

local service = {
  local host = 'api.internal',  // 对象内的局部变量，可供字段值使用

  name: serviceName,
  port: 8080,

  // :: 隐藏字段：内部可用，但不会出现在 JSON/YAML 输出中
  protocol:: 'http',
  // ::: 强制可见（常用于覆盖继承来的隐藏字段）
  endpoint::: 'api.internal:8080',

  // 方法就是函数字段；隐藏方法不会被序列化
  withPort(p):: self { port: p },

  // 字段值可以引用 self / 其他字段
  url: '%s://%s:%d' % [self.protocol, host, self.port],

  // 字段名可以是表达式（注意：字段名里不能引用对象内的 local）
  ['meta_' + serviceName]: { team: 'platform' },

  // 对象断言：字段被访问 / 对象被输出时校验
  assert self.port > 0 && self.port < 65536 : 'port 越界',
};

{
  service: service,

  // 不可变式更新：返回新对象，原对象不变
  updatedPort: service.withPort(9090).port,
  originalPort: service.port,

  // 字段可见性：默认输出不含隐藏字段
  visibleFields: std.objectFields(service),
  allFields: std.objectFieldsAll(service),
  hiddenFieldReadable: service.protocol,

  // 动态访问
  dynamicAccess: service.name,

  // 对象推导：从数组生成对象
  portsByService: {
    [svc.name]: svc.port
    for svc in [
      { name: 'api', port: 8000 },
      { name: 'web', port: 8001 },
      { name: 'worker', port: 8002 },
    ]
  },

  // 投影：只保留指定字段
  projected: {
    [k]: service[k]
    for k in ['name', 'port']
  },

  // 对象 + 是浅合并：同名嵌套对象会被整体替换
  shallowMerged: { db: { host: 'localhost', port: 5432 } } + { db: { port: 6543 } },
  // 需要递归合并时用 std.mergePatch（RFC 7396）或字段级 +:
  deepMerged: std.mergePatch(
    { db: { host: 'localhost', port: 5432 } },
    { db: { port: 6543 } }
  ),

  // self 指向最近的对象，$ 始终指向当前文件的最外层对象
  nested: {
    whoAmI: 'nested',
    selfName: self.whoAmI,  // self 指向 nested
    rootServiceName: $.service.name,  // $ 指向文件最外层对象
  },
}
