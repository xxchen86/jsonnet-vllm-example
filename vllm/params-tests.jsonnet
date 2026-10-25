// 阶段 1 断言测试：jsonnet vllm/params-tests.jsonnet
// 断言失败时 jsonnet 以非 0 退出。

local launch = import 'lib/launch.libsonnet';
local defaultTemplate = import 'templates/deepseek-v41-flash-h200.libsonnet';

local generate(config) = launch.generate(defaultTemplate, config);
local validate(config) = launch.validate(defaultTemplate, config);

local has(obj, key) = std.type(obj) == 'object' && std.objectHas(obj, key);

local hasErr(errors, needle) =
  std.length(std.findSubstr(needle, std.join('; ', errors))) > 0;

local base = { nodes: 1, gpusPerNode: 8, gpuMemoryGiB: 141 };

local single = generate(base);
local gb200 = generate({ nodes: 1, gpusPerNode: 4, gpuMemoryGiB: 192 });
local multiPp = generate(base { nodes: 2, parallelMode: 'tp-pp' });
local multiTp = generate(base { nodes: 2, parallelMode: 'tp' });
local multiMp = generate(base { nodes: 2, parallelMode: 'tp', distributedBackend: 'mp' });
local totalGpusTp = generate({ nodes: 2, totalGpus: 16, parallelMode: 'tp' });
local totalGpusPp = generate({ nodes: 2, totalGpus: 16 });
local noSpec = generate(base { speculative: false });
local noThink = generate(base { thinking: false });
local noTool = generate(base { toolCalling: false });
local mm = generate(base { multimodal: true });
local threeNodes = generate(base { nodes: 3 });
local lowVram = generate({ nodes: 1, gpusPerNode: 4, gpuMemoryGiB: 141 });
local effortAlias = generate(base { reasoningEffort: 'max' });
local effortNone = generate(base { reasoningEffort: 'none' });
local withMounts = generate({
  nodes: 1,
  gpusPerNode: 8,
  modelHostPath: '/host/models/DeepSeek-V4.1-Flash',
  modelPath: '/models/DeepSeek-V4.1-Flash',
  extraEnv: { FOO: 1, BAR: true, SKIP: null },
  extraMounts: [{ hostPath: '/host/data', containerPath: '/data' }],
});

local badTp = validate(base { nodes: 2, tensorParallel: 5 });
local badTotal = validate({ nodes: 2, totalGpus: 15 });
local badEffort = validate(base { reasoningEffort: 'ultra' });
local badIps = validate(base { nodes: 2, nodeIps: ['10.0.0.10'] });
local badMount = validate({ modelHostPath: '/host/models' });
local badExtra = validate(base { extraArgs: ['ok', 1] });

{
  // 产物 schema：只有 vLLM 原生分区，没有旧的内部结构 / 渲染结果
  assert single.apiVersion == 'vllm-params/v1' : 'params apiVersion',
  assert std.objectFields(single) == [
    'apiVersion',
    'container',
    'deployment',
    'extras',
    'scenario',
    'serve',
    'warnings',
  ] : 'params top-level keys',
  assert !has(single, 'meta') : 'no meta',
  assert !has(single, 'input') : 'no input',
  assert !has(single, 'parallel') : 'no parallel',
  assert !has(single, 'features') : 'no features',
  assert !has(single, 'environment') : 'no top-level environment',
  assert !has(single.serve, 'argv') : 'serve has no argv',
  assert !has(single.serve, 'command') : 'serve has no command',
  assert !has(single.deployment, 'commands') : 'deployment has no commands',
  assert !has(single.deployment, 'mode') : 'deployment has no mode',

  // 单机 8 卡 -> TP8 / PP1，参数名与 vLLM 原生参数一致
  assert single.serve.model == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'single model',
  assert single.serve.served_model_name == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'single served name',
  assert single.serve.tokenizer_mode == 'deepseek_v41' : 'single tokenizer mode',
  assert single.serve.tensor_parallel_size == 8 : 'single TP',
  assert single.serve.pipeline_parallel_size == 1 : 'single PP',
  assert single.serve.enable_expert_parallel == true : 'single EP',
  assert single.serve.max_model_len == 1048576 : 'single max model len',
  assert single.serve.max_num_batched_tokens == 16384 : 'single max batched tokens',
  assert single.serve.max_cudagraph_capture_size == 1024 : 'single cudagraph size',
  assert single.serve.gpu_memory_utilization == 0.9 : 'single gpu mem util',
  assert single.serve.speculative_config.method == 'dspark' : 'single speculative method',
  assert single.serve.speculative_config.num_speculative_tokens == 5 : 'single speculative tokens',
  assert single.serve.reasoning_parser == 'deepseek_v41' : 'single reasoning parser',
  assert single.serve.default_chat_template_kwargs.thinking == true : 'single thinking',
  assert single.serve.default_chat_template_kwargs.reasoning_effort == 50 : 'single effort',
  assert single.serve.tool_call_parser == 'deepseek_v41' : 'single tool parser',
  assert single.serve.enable_auto_tool_choice == true : 'single auto tool choice',
  assert single.serve.language_model_only == true : 'single language model only',
  assert single.serve.disable_uvicorn_access_log == true : 'single disable access log',
  assert !has(single.serve, 'api_key') : 'single no api key',
  assert !has(single.serve, 'max_num_seqs') : 'single no max num seqs',
  assert !has(single.serve, 'enforce_eager') : 'single no enforce eager',

  assert single.deployment.nodes == 1 : 'single nodes',
  assert single.deployment.gpus_per_node == 8 : 'single gpus per node',
  assert single.deployment.node_ips == ['10.0.0.10'] : 'single node ips',
  assert single.deployment.distributed_executor_backend == 'local' : 'single backend',
  assert !has(single.deployment, 'ray_port') : 'single no ray port',
  assert !has(single.deployment, 'master_port') : 'single no master port',

  assert single.container.image == 'vllm/vllm-openai:deepseekv41-flash-0909' : 'single image',
  assert single.container.environment == {
    VLLM_ENGINE_READY_TIMEOUT_S: '3600',
    VLLM_USE_RUST_FRONTEND: '1',
  } : 'single environment',
  assert single.container.mounts == [] : 'single no mounts',
  assert single.container.shm_size == '32g' : 'single shm size',
  assert single.container.network_host == true : 'single network host',
  assert single.container.name_prefix == 'dsv41' : 'single name prefix',
  assert single.extras == { serve_args: [], docker_args: [] } : 'single extras',
  assert single.warnings == [] : 'single no warnings',

  // 单机 4 卡（GB200 NVL4）-> TP4
  assert gb200.serve.tensor_parallel_size == 4 : 'GB200 TP',
  assert gb200.serve.enable_expert_parallel == true : 'GB200 EP',
  assert gb200.warnings == [] : 'GB200 no warnings',

  // 多机默认 -> 机内 TP、机间 PP，Ray 后端
  assert multiPp.serve.tensor_parallel_size == 8 : 'multiPp TP',
  assert multiPp.serve.pipeline_parallel_size == 2 : 'multiPp PP',
  assert multiPp.deployment.distributed_executor_backend == 'ray' : 'multiPp backend',
  assert multiPp.deployment.node_ips == ['10.0.0.10', '10.0.0.11'] : 'multiPp IPs',
  assert multiPp.deployment.ray_port == 6379 : 'multiPp ray port',
  assert !has(multiPp.deployment, 'master_port') : 'multiPp no master port',

  // parallelMode=tp -> 跨机 TP
  assert multiTp.serve.tensor_parallel_size == 16 : 'multiTp TP',
  assert multiTp.serve.pipeline_parallel_size == 1 : 'multiTp PP',
  assert multiTp.deployment.distributed_executor_backend == 'ray' : 'multiTp backend',

  // 只传 totalGpus 时，自动推导每机卡数
  assert totalGpusTp.deployment.gpus_per_node == 8 : 'totalGpus derives gpusPerNode',
  assert totalGpusTp.serve.tensor_parallel_size == 16 : 'totalGpus TP',
  assert totalGpusPp.serve.tensor_parallel_size == 8 : 'totalGpus auto TP',
  assert totalGpusPp.serve.pipeline_parallel_size == 2 : 'totalGpus auto PP',

  // mp 后端
  assert multiMp.deployment.distributed_executor_backend == 'mp' : 'multiMp backend',
  assert multiMp.deployment.master_port == 29501 : 'multiMp master port',
  assert !has(multiMp.deployment, 'ray_port') : 'multiMp no ray port',

  // 功能开关 -> vLLM 原生参数
  assert !has(noSpec.serve, 'speculative_config') : 'speculative off removes config',
  assert !has(noThink.serve, 'reasoning_parser') : 'thinking off removes parser',
  assert noThink.serve.default_chat_template_kwargs.thinking == false : 'thinking off kwargs',
  assert noThink.serve.default_chat_template_kwargs.reasoning_effort == 'none' : 'thinking off effort',
  assert !has(noTool.serve, 'tool_call_parser') : 'tool off removes parser',
  assert !has(noTool.serve, 'enable_auto_tool_choice') : 'tool off removes auto choice',
  assert !has(mm.serve, 'language_model_only') : 'multimodal removes language-model-only',
  assert mm.serve.mm_encoder_tp_mode == 'data' : 'multimodal mm encoder mode',
  assert effortAlias.serve.default_chat_template_kwargs.reasoning_effort == 100 : 'max alias maps to 100',
  assert !has(effortNone.serve, 'reasoning_parser') : 'effort none disables thinking',
  assert effortNone.serve.default_chat_template_kwargs.thinking == false : 'effort none kwargs',
  assert effortNone.serve.default_chat_template_kwargs.reasoning_effort == 'none' : 'effort none effort',

  // 环境变量 / 挂载归一化
  assert withMounts.serve.model == '/models/DeepSeek-V4.1-Flash' : 'modelPath becomes serve.model',
  assert std.length(withMounts.container.mounts) == 2 : 'model + extra mounts',
  assert withMounts.container.mounts[0] == {
    host_path: '/host/models/DeepSeek-V4.1-Flash',
    container_path: '/models/DeepSeek-V4.1-Flash',
    read_only: true,
  } : 'model mount normalized',
  assert withMounts.container.mounts[1] == {
    host_path: '/host/data',
    container_path: '/data',
    read_only: true,
  } : 'extra mount normalized',
  assert withMounts.container.environment.FOO == '1' : 'env number stringified',
  assert withMounts.container.environment.BAR == 'true' : 'env boolean stringified',
  assert !has(withMounts.container.environment, 'SKIP') : 'env null dropped',

  // 警告与负例
  assert std.length(threeNodes.warnings) > 0 : 'PP3 should warn about 40 layers',
  assert hasErr(threeNodes.warnings, 'PP=3') : 'PP3 warning text',
  assert std.length(lowVram.warnings) > 0 : '4x141GB should warn about VRAM floor',
  assert hasErr(lowVram.warnings, '614') : 'VRAM warning text',

  assert hasErr(badTp.errors, 'TP × PP') : 'bad TP error',
  assert hasErr(badTotal.errors, 'totalGpus 必须能被 nodes 整除') : 'bad totalGpus error',
  assert hasErr(badEffort.errors, 'reasoningEffort') : 'bad effort error',
  assert hasErr(badIps.errors, 'nodeIps 数量必须等于 nodes') : 'bad nodeIps error',
  assert hasErr(badMount.errors, 'modelHostPath') : 'bad model mount error',
  assert hasErr(badExtra.errors, 'extraArgs 每项必须是字符串') : 'bad extraArgs error',

  summary: {
    cases: 16,
    negatives: 6,
    single: single.serve.tensor_parallel_size,
    multiRay: multiPp.serve.pipeline_parallel_size,
    multiMp: multiMp.deployment.distributed_executor_backend,
    warnings: {
      threeNodes: threeNodes.warnings,
      lowVram: lowVram.warnings,
    },
  },
}
