// 阶段 1：把场景配置生成为 vLLM 原生参数产物（vllm-params/v1）。
//
// 用法：
//   jsonnet vllm/generate-params.jsonnet --tla-code-file config=vllm/params/single-h200-8gpu.json

local params = import 'lib/params.libsonnet';

function(config={}) params.generate(config)
