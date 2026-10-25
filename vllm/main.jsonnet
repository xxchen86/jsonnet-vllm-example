// DeepSeek-V4.1-Flash vLLM 启动参数生成入口。
//
// 用法（TLA，推荐用 JSON 文件承载外部输入）：
//   jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/single-h200-8gpu.json
//
// 也可以直接内联覆盖：
//   jsonnet vllm/main.jsonnet --tla-code config='{nodes: 2, gpusPerNode: 8, speculative: true}'
//
// 所有字段的默认值见 lib/serve.libsonnet 的 defaults。

local serve = import 'lib/serve.libsonnet';

function(config={}) serve.render(config)
