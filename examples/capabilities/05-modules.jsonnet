// 05 · 模块化：import / importstr / 参数化库
// 运行：jsonnet examples/capabilities/05-modules.jsonnet

local deployment = import 'lib/deployment.libsonnet';
local notes = importstr 'lib/notes.txt';
local data = import 'lib/data.json';

{
  // 参数化库：函数返回基础对象，调用方继续用 + 覆盖
  api: deployment('api', 8080) {
    spec+: { replicas: 3 },
  },
  worker: deployment('worker', 9090),

  // importstr 读取原始文本（不做 Jsonnet 解析）
  notes: notes,

  // JSON 是合法的 Jsonnet 子集，可以直接 import
  data: data,
}
