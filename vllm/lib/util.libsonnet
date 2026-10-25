// 通用小工具：类型判断、默认值读取、校验错误文本、功能开关归一化。

{
  isObj(v):: std.type(v) == 'object',
  isArr(v):: std.type(v) == 'array',
  isStr(v):: std.type(v) == 'string',
  isBool(v):: std.type(v) == 'boolean',
  isNum(v):: std.type(v) == 'number',
  isInt(v):: $.isNum(v) && std.floor(v) == v,

  getOr(obj, field, fallback)::
    if std.objectHas(obj, field) && obj[field] != null then obj[field] else fallback,

  asBool(value, fallback)::
    if std.type(value) == 'boolean' then value else fallback,

  str(value)::
    if std.type(value) == 'object' || std.type(value) == 'array' then
      std.manifestJsonMinified(value)
    else
      std.toString(value),

  intAtLeast(field, value, min)::
    if !$.isInt(value) || value < min then
      ['%s 必须是 >= %d 的整数（当前：%s，类型：%s）' % [field, min, $.str(value), std.type(value)]]
    else [],

  intInRange(field, value, min, max)::
    if !$.isInt(value) || value < min || value > max then
      ['%s 必须是 %d-%d 之间的整数（当前：%s，类型：%s）' % [field, min, max, $.str(value), std.type(value)]]
    else [],

  numberAtLeast(field, value, min)::
    if std.type(value) != 'number' || value < min then
      ['%s 必须是 >= %s 的数字（当前：%s，类型：%s）' % [field, $.str(min), $.str(value), std.type(value)]]
    else [],

  boolError(field, value)::
    if std.type(value) != 'boolean' then
      ['%s 必须是布尔值（当前：%s，类型：%s）' % [field, $.str(value), std.type(value)]]
    else [],

  // 布尔开关 / 对象两种写法都接受：
  //   speculative: true
  //   speculative: { enabled: true, numSpeculativeTokens: 3 }
  featureInput(value)::
    if value == null then {}
    else if std.type(value) == 'object' then value
    else { enabled: value },
}
