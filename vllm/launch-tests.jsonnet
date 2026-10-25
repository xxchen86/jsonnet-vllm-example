// 静态模板 / 动态 INPUT 测试：jsonnet vllm/launch-tests.jsonnet
//
// 覆盖：
//   - 高层静态模板（helper）与底层静态模板（v1 对象/函数）等价；
//   - helper 分组函数与内联条件写法等价；
//   - 六个自动化模块的输出；
//   - 自定义模型 profile 的数据驱动与 warning；
//   - 负例与兼容行为。

local h = import 'lib/launch-helpers.libsonnet';
local launch = import 'lib/launch.libsonnet';
local defaultTemplate = import 'templates/deepseek-v41-flash-h200.libsonnet';
local hardware = import 'templates/profiles/hardware/h200.libsonnet';
local model = import 'templates/profiles/models/deepseek-v41-flash.libsonnet';

local has(obj, key) = std.type(obj) == 'object' && std.objectHas(obj, key);
local hasErr(errors, needle) =
  std.length(std.findSubstr(needle, std.join('; ', errors))) > 0;

local base = { nodes: 1, gpusPerNode: 8, gpuMemoryGiB: 141 };

local launchCfg = {
  host: '0.0.0.0',
  port: 8000,
  environment: { VLLM_ENGINE_READY_TIMEOUT_S: '3600' },
  parallelMode: 'auto',
  distributedBackend: 'ray',
  nodeIpPattern: '10.0.0.%d',
  nodeIpStart: 10,
  rayPort: 6379,
  masterPort: 29501,
};

local generate(config) = launch.generate(defaultTemplate, config);
local validate(config) = launch.validate(defaultTemplate, config);
local ctxFor(config) = h.context({
  model: model,
  hardware: hardware,
  launch: launchCfg,
  config: config,
});

// 用任意 model/hardware profile 组装一个高层静态模板；验证 profile 数据驱动。
local makeDeclaration(modelProfile, hardwareProfile) =
  function(config={})
    local ctx = h.context({
      model: modelProfile,
      hardware: hardwareProfile,
      launch: launchCfg,
      config: config,
    });
    h.params({
      ctx: ctx,
      serve:
        {
          model: if ctx.input.modelPath != null then ctx.input.modelPath else ctx.input.model,
          served_model_name: ctx.input.servedModelName,
          tokenizer_mode: ctx.model.capabilities.tokenizerMode,
          host: ctx.input.host,
          port: ctx.input.port,
          tensor_parallel_size: ctx.automation.parallel.tensorParallel,
          pipeline_parallel_size: ctx.automation.parallel.pipelineParallel,
          max_model_len: ctx.input.maxModelLen,
          max_num_batched_tokens: ctx.input.maxNumBatchedTokens,
          max_cudagraph_capture_size: ctx.input.maxCudagraphCaptureSize,
          gpu_memory_utilization: ctx.input.gpuMemoryUtilization,
          default_chat_template_kwargs: ctx.automation.features.chatTemplateKwargs,
        }
        + h.parallelServeParams(ctx)
        + h.featuresServeParams(ctx)
        + h.inputServeParams(ctx),
      deployment:
        {
          nodes: ctx.input.nodes,
          gpus_per_node: ctx.automation.worldSize.gpusPerNode,
          node_ips: ctx.automation.network.nodeIps,
          distributed_executor_backend: ctx.automation.backend.backend,
        }
        + h.backendPortParams(ctx),
      container: {
        image: ctx.input.image,
        environment: ctx.automation.container.environment,
        mounts: ctx.automation.container.mounts,
        shm_size: ctx.input.dockerShmSize,
        network_host: ctx.input.dockerNetworkHost,
        name_prefix: ctx.input.containerNamePrefix,
      },
      extras: {
        serve_args: ctx.input.extraArgs,
        docker_args: ctx.input.extraDockerArgs,
      },
    });

// ---------------------------------------------------------------------------
// 场景与模块
// ---------------------------------------------------------------------------

local sSingle = import 'params/single-h200-8gpu.json';
local sOff = import 'params/single-h200-8gpu-switches-off.json';
local sGb200 = import 'params/single-gb200-4gpu.json';
local sRay = import 'params/multi-h200-2x8-ray.json';
local sMp = import 'params/multi-h200-2x8-mp-tp16.json';

local cSingle = ctxFor(sSingle);
local cOff = ctxFor(sOff);
local cGb200 = ctxFor(sGb200);
local cRay = ctxFor(sRay);
local cMp = ctxFor(sMp);

// ---------------------------------------------------------------------------
// helper 与内联写法
// ---------------------------------------------------------------------------

local helperCtx = ctxFor(base);

local inlineParallel =
  if helperCtx.automation.parallel.expertParallel then
    { enable_expert_parallel: true }
  else {};

local inlineFeatures =
  local f = helperCtx.automation.features;
  (if f.speculative.enabled then { speculative_config: f.speculative.config } else {}) +
  (if f.thinking.enabled && f.thinking.parser != null then
     { reasoning_parser: f.thinking.parser }
   else {}) +
  (if f.toolCalling.enabled && f.toolCalling.parser != null then
     {
       tool_call_parser: f.toolCalling.parser,
       enable_auto_tool_choice: true,
     }
   else {}) +
  (if f.multimodal.enabled then
     { mm_encoder_tp_mode: f.multimodal.encoderTpMode }
   else
     { language_model_only: true });

local inlineInput =
  (if helperCtx.input.apiKey != null then { api_key: helperCtx.input.apiKey } else {}) +
  (if helperCtx.input.maxNumSeqs != null then { max_num_seqs: helperCtx.input.maxNumSeqs } else {}) +
  (if helperCtx.input.disableUvicornAccessLog then { disable_uvicorn_access_log: true } else {}) +
  (if helperCtx.input.enforceEager then { enforce_eager: true } else {});

local inlineBackend =
  (if helperCtx.automation.backend.isRay then { ray_port: helperCtx.input.rayPort } else {}) +
  (if helperCtx.automation.backend.isMp then { master_port: helperCtx.input.masterPort } else {});

// ---------------------------------------------------------------------------
// 自定义模型 profile
// ---------------------------------------------------------------------------

local tinyModel = model {
  id: 'acme/tiny',
  servedModelName: 'acme/tiny',
  layers: 28,
  weightsGiB: 14,
  vramFloorGiB: 17,
  image: 'acme/tiny:v1',
  capabilities: {
    tokenizerMode: 'auto',
    reasoningParser: null,
    toolParser: null,
    supportsMultimodal: false,
  },
  runtime: {
    containerNamePrefix: 'tiny',
    environment: {},
  },
  recipe: {
    maxModelLen: 4096,
    maxNumBatchedTokens: 1024,
    maxCudagraphCaptureSize: 64,
    gpuMemoryUtilization: 0.8,
  },
  features: {
    speculative: false,
    speculativeDefaults: {},
    thinking: false,
    reasoningEffort: 50,
    toolCalling: false,
    multimodal: false,
    mmEncoderTpMode: 'data',
    expertParallel: false,
  },
};

local tinyTemplate = makeDeclaration(tinyModel, hardware);
local tinyOut = launch.generate(tinyTemplate, {
  nodes: 3,
  gpusPerNode: 1,
  gpuMemoryGiB: 4,
});

// ---------------------------------------------------------------------------
// 兼容与负例
// ---------------------------------------------------------------------------

local high = generate(base);

local lowViaArtifact = launch.generate(high, {});
local lowViaFunction = launch.generate(function(config={}) high, {});
local lowViaLiteral = launch.generate({
  apiVersion: 'vllm-params/v1',
  scenario: 'literal',
  serve: high.serve,
  deployment: high.deployment,
  container: high.container,
  extras: high.extras,
  warnings: high.warnings,
}, {});

local conflict = validate(base { nodes: 2, totalGpus: 16, gpusPerNode: 4 });
local artifactAsConfig = validate({ apiVersion: 'vllm-params/v1' });

local noReasoning = model {
  capabilities: model.capabilities { reasoningParser: null },
};
local noReasoningCtx = h.context({
  model: noReasoning,
  hardware: hardware,
  launch: launchCfg,
  config: base,
});

local noMm = model {
  capabilities: model.capabilities { supportsMultimodal: false },
};
local noMmCtx = h.context({
  model: noMm,
  hardware: hardware,
  launch: launchCfg,
  config: base { multimodal: true },
});

local badType = launch.validate(42, {});
local badVersion = launch.validate({
  apiVersion: 'vllm-params/v2',
  serve: {},
  deployment: {},
  container: {},
  extras: {},
}, {});
local missingPartition = launch.validate({
  apiVersion: 'vllm-params/v1',
  serve: {},
  deployment: {},
  container: {},
}, {});

local otherModel = generate(base { model: 'other/model' });
local otherModelNullServed = generate(base { model: 'other/model', servedModelName: null });

local envCtx = ctxFor(base {
  extraEnv: {
    FOO: 'bar',
    VLLM_USE_RUST_FRONTEND: 'override',
    SKIP: null,
  },
});

{
  // 默认静态模板的关键字段（完整 schema 由 params-tests 覆盖）
  assert high.apiVersion == 'vllm-params/v1' : 'high apiVersion',
  assert high.warnings == [] : 'high no warnings',
  assert high.serve.tensor_parallel_size == 8 : 'high TP8',
  assert high.serve.pipeline_parallel_size == 1 : 'high PP1',
  assert high.deployment.distributed_executor_backend == 'local' : 'high local',
  assert high.container.environment.VLLM_ENGINE_READY_TIMEOUT_S == '3600' : 'high env',

  // 底层静态模板三种入口
  assert lowViaArtifact == high : 'artifact as template',
  assert lowViaFunction == high : 'function returning artifact',
  assert lowViaLiteral.serve == high.serve : 'literal serve',
  assert lowViaLiteral.deployment == high.deployment : 'literal deployment',
  assert lowViaLiteral.container == high.container : 'literal container',
  assert lowViaLiteral.extras == high.extras : 'literal extras',

  // helper 分组函数 == 内联条件写法
  assert h.parallelServeParams(helperCtx) == inlineParallel : 'parallel helper',
  assert h.featuresServeParams(helperCtx) == inlineFeatures : 'features helper',
  assert h.inputServeParams(helperCtx) == inlineInput : 'input helper',
  assert h.backendPortParams(helperCtx) == inlineBackend : 'backend helper',

  // 默认值映射
  assert h.defaults({ model: model, hardware: hardware, launch: launchCfg }) == {
    scenario: 'custom',
    model: 'deepseek-ai/DeepSeek-V4.1-Flash',
    servedModelName: 'deepseek-ai/DeepSeek-V4.1-Flash',
    modelPath: null,
    modelHostPath: null,
    image: 'vllm/vllm-openai:deepseekv41-flash-0909',
    host: '0.0.0.0',
    port: 8000,
    apiKey: null,
    nodes: 1,
    totalGpus: null,
    gpusPerNode: 8,
    gpuMemoryGiB: 141,
    modelLayers: 40,
    parallelMode: 'auto',
    tensorParallel: null,
    pipelineParallel: null,
    expertParallel: true,
    distributedBackend: 'ray',
    maxModelLen: 1048576,
    maxNumBatchedTokens: 16384,
    maxCudagraphCaptureSize: 1024,
    gpuMemoryUtilization: 0.9,
    maxNumSeqs: null,
    enforceEager: false,
    disableUvicornAccessLog: true,
    speculative: true,
    thinking: true,
    reasoningEffort: 50,
    toolCalling: true,
    multimodal: false,
    mmEncoderTpMode: 'data',
    nodeIpPattern: '10.0.0.%d',
    nodeIpStart: 10,
    nodeIps: [],
    rayPort: 6379,
    masterPort: 29501,
    containerNamePrefix: 'dsv41',
    dockerShmSize: '32g',
    dockerNetworkHost: true,
    hfHubOffline: false,
    extraEnv: {},
    extraMounts: [],
    extraDockerArgs: [],
    extraArgs: [],
  } : 'defaults mapping',

  // 五个场景的自动化模块输出
  assert cSingle.errors == [] : 'single errors',
  assert cSingle.automation.parallel.tensorParallel == 8 : 'single TP',
  assert cSingle.automation.parallel.pipelineParallel == 1 : 'single PP',
  assert cSingle.automation.backend.backend == 'local' : 'single backend',
  assert cSingle.automation.network.nodeIps == ['10.0.0.10'] : 'single ips',
  assert cSingle.automation.features.speculative.enabled == true : 'single spec',
  assert cSingle.automation.features.chatTemplateKwargs == {
    thinking: true,
    reasoning_effort: 50,
  } : 'single kwargs',
  assert cSingle.automation.container.environment == {
    VLLM_ENGINE_READY_TIMEOUT_S: '3600',
    VLLM_USE_RUST_FRONTEND: '1',
  } : 'single env',

  assert cOff.automation.features.speculative.enabled == false : 'off spec',
  assert cOff.automation.features.thinking.enabled == false : 'off thinking',
  assert cOff.automation.features.toolCalling.enabled == false : 'off tool',
  assert cOff.automation.features.multimodal.enabled == true : 'off multimodal',
  assert cOff.automation.features.multimodal.textOnly == false : 'off textOnly',
  assert cOff.automation.features.multimodal.encoderTpMode == 'data' : 'off mm mode',

  assert cGb200.automation.worldSize.gpusPerNode == 4 : 'gb200 gpus',
  assert cGb200.input.gpuMemoryGiB == 192 : 'gb200 memory',
  assert cGb200.automation.parallel.tensorParallel == 4 : 'gb200 TP',

  assert cRay.automation.parallel.tensorParallel == 8 : 'ray TP',
  assert cRay.automation.parallel.pipelineParallel == 2 : 'ray PP',
  assert cRay.automation.backend.backend == 'ray' : 'ray backend',
  assert cRay.automation.backend.isRay == true : 'ray isRay',
  assert cRay.automation.backend.rayPort == 6379 : 'ray port',
  assert cRay.automation.network.nodeIps == ['10.0.0.10', '10.0.0.11'] : 'ray ips',

  assert cMp.automation.worldSize.gpusPerNode == 8 : 'mp derived gpus',
  assert cMp.automation.parallel.tensorParallel == 16 : 'mp TP',
  assert cMp.automation.parallel.pipelineParallel == 1 : 'mp PP',
  assert cMp.automation.backend.backend == 'mp' : 'mp backend',
  assert cMp.automation.backend.isMp == true : 'mp isMp',
  assert cMp.automation.backend.masterPort == 29501 : 'mp port',
  assert hasErr(cMp.warnings, '跨机 TP') : 'mp cross-node warning',

  // 自定义模型 profile
  assert tinyOut.serve.tokenizer_mode == 'auto' : 'tiny tokenizer',
  assert tinyOut.serve.max_model_len == 4096 : 'tiny recipe',
  assert tinyOut.serve.tensor_parallel_size == 1 : 'tiny TP',
  assert tinyOut.serve.pipeline_parallel_size == 3 : 'tiny PP',
  assert tinyOut.container.image == 'acme/tiny:v1' : 'tiny image',
  assert tinyOut.container.name_prefix == 'tiny' : 'tiny prefix',
  assert !has(tinyOut.serve, 'speculative_config') : 'tiny no spec',
  assert !has(tinyOut.serve, 'reasoning_parser') : 'tiny no reasoning',
  assert !has(tinyOut.serve, 'tool_call_parser') : 'tiny no tool',
  assert tinyOut.serve.language_model_only == true : 'tiny language only',
  assert hasErr(tinyOut.warnings, '模型 28 层不能被 PP=3 整除') : 'tiny PP warning',
  assert hasErr(tinyOut.warnings, '低于官方 17 GB') : 'tiny vram warning',
  assert hasErr(tinyOut.warnings, '14 GB 权重') : 'tiny weights warning',

  // 兼容行为
  assert hasErr(conflict.errors, '冲突') : 'totalGpus conflict',
  assert hasErr(artifactAsConfig.errors, '请把该文件传给 generate-params 的 template 参数') : 'artifact as config',
  assert otherModel.serve.served_model_name == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'served name stays',
  assert otherModelNullServed.serve.served_model_name == 'other/model' : 'served name fallback',
  assert otherModel.serve.model == 'other/model' : 'model override',
  assert envCtx.automation.container.environment.FOO == 'bar' : 'extra env',
  assert envCtx.automation.container.environment.VLLM_USE_RUST_FRONTEND == 'override' : 'env override',
  assert !has(envCtx.automation.container.environment, 'SKIP') : 'env null dropped',

  // 能力与静态模板负例
  assert hasErr(noReasoningCtx.errors, 'thinking 需要模型模板提供') : 'missing reasoning parser',
  assert hasErr(noMmCtx.errors, '模板不支持 multimodal') : 'unsupported multimodal',
  assert hasErr(badType.errors, 'template 必须是函数或 vllm-params/v1 对象') : 'bad declaration type',
  assert hasErr(badVersion.errors, 'apiVersion') : 'bad declaration version',
  assert hasErr(missingPartition.errors, '缺少对象分区 extras') : 'missing partition',

  summary: {
    scenarios: 5,
    modules: ['worldSize', 'parallel', 'network', 'backend', 'features', 'container'],
    tinyWarnings: tinyOut.warnings,
    mpWarnings: cMp.warnings,
  },
}
