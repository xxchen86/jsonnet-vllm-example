// 可复用工具库：Jsonnet 的 import 不需要任何包管理，相对路径即可
{
  // 把数组按指定字段转成以该字段为 key 的对象（例如按 name 建索引）
  indexBy(arr, key):: {
    [item[key]]: item
    for item in arr
  },

  // 四舍五入到 n 位小数
  roundTo(x, n):: std.round(x * std.pow(10, n)) / std.pow(10, n),

  // 生成一组带序号后缀的名字，如 genNames('worker', 3) -> ['worker-0', ...]
  genNames(prefix, count):: [
    '%s-%d' % [prefix, i]
    for i in std.range(0, count - 1)
  ],
}
