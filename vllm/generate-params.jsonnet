// 阶段 1：把静态模板 + 动态 INPUT 生成为 vLLM 原生参数产物（vllm-params/v1）。
//
// 用法：
//   jsonnet vllm/generate-params.jsonnet --tla-code-file config=vllm/params/single-h200-8gpu.json
//   jsonnet vllm/generate-params.jsonnet --tla-code-file template=vllm/out/foo.params.json
//
// template 可以是函数（高层静态模板）或 vllm-params/v1 对象（底层静态模板）；
// 省略时使用默认高层静态模板。

local launch = import 'lib/launch.libsonnet';
local defaultTemplate = import 'templates/deepseek-v41-flash-h200.libsonnet';

function(config={}, template=defaultTemplate) launch.generate(template, config)
