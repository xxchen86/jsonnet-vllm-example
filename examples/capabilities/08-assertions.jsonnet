// 08 · 断言与惰性求值
// 运行：jsonnet examples/capabilities/08-assertions.jsonnet

local checked = {
  value: 3,
  // 对象断言：对象被访问/输出时检查
  assert self.value > 0 : 'value 必须为正数',
  double: self.value * 2,
};

// 惰性求值：未被使用的字段不会求值，所以这里的 error 不会触发
local lazy = {
  ok: 1,
  boom:: error '只有访问 boom 时才会报错',
};

// 顶层断言：条件为假时求值失败
assert std.length([1, 2, 3]) == 3 : '长度断言失败';

{
  checked: checked,
  assertEqual: std.assertEqual(checked.double, 6),
  lazy: lazy,

  // std.trace 会把消息写到 stderr 并原样返回第二个参数，适合调试
  trace: std.trace('这条消息只会出现在 stderr', 'trace 的返回值'),

  // 取消下面这行的注释，就会因为访问惰性字段而失败：
  // crash: lazy.boom,
}
