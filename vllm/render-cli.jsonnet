// 阶段 2：读取 vLLM 原生参数产物（vllm-params/v1），渲染 argv / Docker / Ray / mp 命令。
//
// 用法：
//   jsonnet vllm/render-cli.jsonnet --tla-code-file params=vllm/out/single-h200-8gpu.params.json

local cli = import 'lib/cli.libsonnet';

function(params) cli.render(params)
