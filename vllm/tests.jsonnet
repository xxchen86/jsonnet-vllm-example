// 运行：jsonnet vllm/tests.jsonnet
// 断言失败时 jsonnet 以非 0 退出。

local vllm = import 'lib/serve.libsonnet';

local hasArg(argv, name) = std.length(std.find(name, argv)) > 0;

local argValue(argv, name) =
  local idx = std.find(name, argv);
  if std.length(idx) == 0 then
    error 'missing arg: ' + name
  else
    argv[idx[0] + 1];

local base = { nodes: 1, gpusPerNode: 8, gpuMemoryGiB: 141 };

local single = vllm.render(base);
local gb200 = vllm.render({ nodes: 1, gpusPerNode: 4, gpuMemoryGiB: 192 });
local multiPp = vllm.render(base { nodes: 2, parallelMode: 'tp-pp' });
local multiTp = vllm.render(base { nodes: 2, parallelMode: 'tp' });
local multiMp = vllm.render(base { nodes: 2, parallelMode: 'tp', distributedBackend: 'mp' });
local totalGpusTp = vllm.render({ nodes: 2, totalGpus: 16, parallelMode: 'tp' });
local totalGpusPp = vllm.render({ nodes: 2, totalGpus: 16 });
local noSpec = vllm.render(base { speculative: false });
local noThink = vllm.render(base { thinking: false });
local noTool = vllm.render(base { toolCalling: false });
local mm = vllm.render(base { multimodal: true });
local threeNodes = vllm.render(base { nodes: 3 });
local lowVram = vllm.render({ nodes: 1, gpusPerNode: 4, gpuMemoryGiB: 141 });
local effortAlias = vllm.render(base { reasoningEffort: 'max' });
local effortNone = vllm.render(base { reasoningEffort: 'none' });

local specConfig = std.parseJson(argValue(single.serve.argv, '--speculative-config'));
local noThinkKwargs = std.parseJson(argValue(noThink.serve.argv, '--default-chat-template-kwargs'));
local effortKwargs = std.parseJson(argValue(effortAlias.serve.argv, '--default-chat-template-kwargs'));
local effortNoneKwargs = std.parseJson(argValue(effortNone.serve.argv, '--default-chat-template-kwargs'));

{
  // 单机 8 卡 -> TP8 / PP1
  assert single.parallel.tensorParallel == 8 : 'single TP should be 8',
  assert single.parallel.pipelineParallel == 1 : 'single PP should be 1',
  assert single.parallel.worldSize == 8 : 'single world size should be 8',
  assert single.parallel.expertParallel == true : 'expert parallel should be enabled',
  assert single.deployment.mode == 'single-node' : 'single deployment mode',
  assert std.length(single.deployment.nodes) == 1 : 'single node count',
  assert single.distributed.backend == 'local' : 'single backend',
  assert single.warnings == [] : 'single should have no warnings',

  // 单机 4 卡（GB200 NVL4）-> TP4
  assert gb200.parallel.tensorParallel == 4 : 'GB200 TP should be 4',
  assert gb200.warnings == [] : '4x192GB should meet VRAM floor',

  // 多机默认 -> 机内 TP、机间 PP
  assert multiPp.parallel.tensorParallel == 8 : 'multiPp TP should be 8',
  assert multiPp.parallel.pipelineParallel == 2 : 'multiPp PP should be 2',
  assert multiPp.deployment.mode == 'ray-multi-node' : 'ray deployment mode',
  assert multiPp.deployment.nodes[0].role == 'head' : 'node 0 is head',
  assert multiPp.deployment.nodes[1].role == 'worker' : 'node 1 is worker',
  assert hasArg(multiPp.deployment.nodes[0].ray.argv, '--head') : 'head ray command',
  assert std.length(std.find('--address=10.0.0.10:6379', multiPp.deployment.nodes[1].ray.argv)) > 0 : 'worker ray address',
  assert argValue(multiPp.serve.argv, '--distributed-executor-backend') == 'ray' : 'serve uses ray',
  assert !hasArg(multiPp.serve.argv, '--nnodes') : 'ray mode must not pass --nnodes',

  // parallelMode=tp -> 跨机 TP
  assert multiTp.parallel.tensorParallel == 16 : 'multiTp TP should be 16',
  assert multiTp.parallel.pipelineParallel == 1 : 'multiTp PP should be 1',
  assert !hasArg(multiTp.serve.argv, '--pipeline-parallel-size') : 'PP1 omitted',

  // 只传 totalGpus 时，自动推导每机卡数
  assert totalGpusTp.input.gpusPerNode == 8 : 'totalGpus derives gpusPerNode',
  assert totalGpusTp.parallel.tensorParallel == 16 : 'totalGpus TP should be 16',
  assert totalGpusPp.parallel.tensorParallel == 8 : 'totalGpus auto TP should be 8',
  assert totalGpusPp.parallel.pipelineParallel == 2 : 'totalGpus auto PP should be 2',

  // mp 后端 -> 每台机器都要跑 vllm serve，worker 带 --headless
  assert multiMp.deployment.mode == 'mp-multi-node' : 'mp deployment mode',
  assert argValue(multiMp.deployment.nodes[0].serve.argv, '--node-rank') == '0' : 'mp head rank 0',
  assert argValue(multiMp.deployment.nodes[1].serve.argv, '--node-rank') == '1' : 'mp worker rank 1',
  assert hasArg(multiMp.deployment.nodes[1].serve.argv, '--headless') : 'mp worker headless',
  assert !hasArg(multiMp.deployment.nodes[0].serve.argv, '--headless') : 'mp head not headless',
  assert multiMp.deployment.nodes[1].ray == null : 'mp mode has no ray command',

  // 功能开关
  assert specConfig.method == 'dspark' : 'default speculative method',
  assert specConfig.num_speculative_tokens == 5 : 'default speculative tokens',
  assert !hasArg(noSpec.serve.argv, '--speculative-config') : 'speculative off removes flag',
  assert noThink.features.thinking.enabled == false : 'thinking off',
  assert !hasArg(noThink.serve.argv, '--reasoning-parser') : 'thinking off removes parser',
  assert noThinkKwargs.thinking == false : 'thinking off kwargs',
  assert noThinkKwargs.reasoning_effort == 'none' : 'thinking off effort none',
  assert !hasArg(noTool.serve.argv, '--tool-call-parser') : 'tool off removes parser',
  assert !hasArg(noTool.serve.argv, '--enable-auto-tool-choice') : 'tool off removes auto choice',
  assert !hasArg(mm.serve.argv, '--language-model-only') : 'multimodal removes language-model-only',
  assert argValue(mm.serve.argv, '--mm-encoder-tp-mode') == 'data' : 'multimodal mm encoder mode',
  assert effortAlias.features.thinking.reasoningEffort == 100 : 'max alias maps to 100',
  assert effortKwargs.reasoning_effort == 100 : 'max alias in kwargs',
  assert effortNone.features.thinking.enabled == false : 'effort none disables thinking',
  assert effortNoneKwargs.thinking == false : 'effort none kwargs',

  // 警告与边界
  assert std.length(threeNodes.warnings) > 0 : 'PP3 should warn about 40 layers',
  assert std.length(lowVram.warnings) > 0 : '4x141GB should warn about VRAM floor',

  summary: {
    cases: 15,
    single: single.parallel.description,
    gb200: gb200.parallel.description,
    multiRay: multiPp.parallel.description,
    multiMp: multiMp.parallel.description,
    warnings: {
      threeNodes: threeNodes.warnings,
      lowVram: lowVram.warnings,
    },
  },
}
