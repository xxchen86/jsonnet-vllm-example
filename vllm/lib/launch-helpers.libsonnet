// 静态模板高层辅助：模型/硬件 profile + 动态 INPUT -> vllm-params/v1 静态模板结果。
//
// 全部是普通 Jsonnet 函数，不是 DSL。模板可以：
//   - 全用：h.context(...) + h.params(...) + 可选参数分组函数；
//   - 用一部分：只拿 ctx.input / ctx.automation 中的值，自己组装对象；
//   - 完全不用：直接写 vllm-params/v1 字面量。
//
// 自动化模块（worldSize / parallel / network / backend / features / container）
// 通过 ctx.automation.<module> 暴露，模板里一眼可见参数来源。

local parallel = import 'parallel.libsonnet';
local util = import 'util.libsonnet';

local apiVersion = 'vllm-params/v1';

local isInt = util.isInt;
local getOr = util.getOr;
local asBool = util.asBool;
local str = util.str;
local featureInput = util.featureInput;

// ---------------------------------------------------------------------------
// 输入默认值
// ---------------------------------------------------------------------------

local defaultsFor(model, hardware, launch) = {
  scenario: 'custom',

  // 模型与镜像
  model: model.id,
  servedModelName: getOr(model, 'servedModelName', model.id),
  modelPath: null,
  modelHostPath: null,
  image: model.image,

  // HTTP 服务
  host: getOr(launch, 'host', '0.0.0.0'),
  port: getOr(launch, 'port', 8000),
  apiKey: null,

  // 机器与并行
  nodes: 1,
  totalGpus: null,
  gpusPerNode: hardware.gpusPerNode,
  gpuMemoryGiB: hardware.gpuMemoryGiB,
  modelLayers: model.layers,
  parallelMode: getOr(launch, 'parallelMode', 'auto'),
  tensorParallel: null,
  pipelineParallel: null,
  expertParallel: model.features.expertParallel,
  distributedBackend: getOr(launch, 'distributedBackend', 'ray'),

  // recipe
  maxModelLen: model.recipe.maxModelLen,
  maxNumBatchedTokens: model.recipe.maxNumBatchedTokens,
  maxCudagraphCaptureSize: model.recipe.maxCudagraphCaptureSize,
  gpuMemoryUtilization: model.recipe.gpuMemoryUtilization,
  maxNumSeqs: null,
  enforceEager: false,
  disableUvicornAccessLog: true,

  // 功能默认
  speculative: model.features.speculative,
  thinking: model.features.thinking,
  reasoningEffort: model.features.reasoningEffort,
  toolCalling: model.features.toolCalling,
  multimodal: model.features.multimodal,
  mmEncoderTpMode: model.features.mmEncoderTpMode,

  // 网络与容器
  nodeIpPattern: getOr(launch, 'nodeIpPattern', '10.0.0.%d'),
  nodeIpStart: getOr(launch, 'nodeIpStart', 10),
  nodeIps: [],
  rayPort: getOr(launch, 'rayPort', 6379),
  masterPort: getOr(launch, 'masterPort', 29501),
  containerNamePrefix: model.runtime.containerNamePrefix,
  dockerShmSize: hardware.shmSize,
  dockerNetworkHost: hardware.networkHost,
  hfHubOffline: false,

  // 逃生舱
  extraEnv: {},
  extraMounts: [],
  extraDockerArgs: [],
  extraArgs: [],
};

// ---------------------------------------------------------------------------
// 输入解析：mergePatch + 旧 getOr 回填语义，保持 null 删除行为
// ---------------------------------------------------------------------------

local resolveInput(model, hardware, launch, config) =
  if std.type(config) != 'object' then
    error 'config 必须是对象'
  else
    local defaults = defaultsFor(model, hardware, launch);
    local cfg = std.mergePatch(defaults, config);
    local modelFallback = getOr(cfg, 'model', defaults.model);
    local rawInput = {
      [k]: getOr(cfg, k, if k == 'servedModelName' then modelFallback else defaults[k])
      for k in std.objectFields(defaults)
    };
    local input = rawInput {
      // 这五个布尔按旧 asBool 语义归一化；rawInput 保留原始值供 boolError。
      expertParallel: asBool(rawInput.expertParallel, true),
      enforceEager: asBool(rawInput.enforceEager, false),
      disableUvicornAccessLog: asBool(rawInput.disableUvicornAccessLog, true),
      dockerNetworkHost: asBool(rawInput.dockerNetworkHost, true),
      hfHubOffline: asBool(rawInput.hfHubOffline, false),
    };
    {
      defaults: defaults,
      rawInput: rawInput,
      input: input,
      configErrors:
        if std.objectHas(config, 'apiVersion') && config.apiVersion == apiVersion then
          ['config 看起来是参数产物 vllm-params/v1；请把该文件传给 generate-params 的 template 参数']
        else [],
    };

// ---------------------------------------------------------------------------
// 自动化模块
// ---------------------------------------------------------------------------

local worldSize(input, config) =
  local nodes = input.nodes;
  local nodeCount = if isInt(nodes) && nodes >= 1 then nodes else 0;
  local totalGpus = input.totalGpus;
  local gpusPerNodeInput = input.gpusPerNode;
  local explicitGpusPerNode =
    if std.type(config) == 'object' &&
       std.objectHas(config, 'gpusPerNode') &&
       config.gpusPerNode != null then
      config.gpusPerNode
    else
      null;
  local totalGpusValid =
    std.type(totalGpus) == 'number' && isInt(totalGpus) && totalGpus >= 1;
  local totalGpusDivisible =
    totalGpusValid && isInt(nodes) && nodes >= 1 && totalGpus % nodes == 0;
  local derivedGpusPerNode = if totalGpusDivisible then totalGpus / nodes else null;
  local gpusPerNode =
    if derivedGpusPerNode != null then derivedGpusPerNode else gpusPerNodeInput;

  local totalGpusErrors =
    if totalGpus == null then
      []
    else if !totalGpusValid then
      ['totalGpus 必须是 >= 1 的整数（当前：%s，类型：%s）' % [str(totalGpus), std.type(totalGpus)]]
    else if !isInt(nodes) || nodes < 1 then
      []
    else if totalGpus % nodes != 0 then
      ['totalGpus 必须能被 nodes 整除：%d / %d 不是整数' % [totalGpus, nodes]]
    else [];

  local conflictErrors =
    if derivedGpusPerNode != null &&
       explicitGpusPerNode != null &&
       explicitGpusPerNode != derivedGpusPerNode then
      ['totalGpus=%d 推导出的 gpusPerNode=%d 与显式 gpusPerNode=%s 冲突' % [
        totalGpus,
        derivedGpusPerNode,
        str(explicitGpusPerNode),
      ]]
    else [];

  {
    nodeCount: nodeCount,
    gpusPerNode: gpusPerNode,
    totalGpusErrors: totalGpusErrors,
    conflictErrors: conflictErrors,
  };

local parallelPlan(input, ws, model) =
  local parallelConfig = {
    nodes: input.nodes,
    gpusPerNode: ws.gpusPerNode,
    gpuMemoryGiB: input.gpuMemoryGiB,
    modelLayers: input.modelLayers,
    parallelMode: input.parallelMode,
    tensorParallel: input.tensorParallel,
    pipelineParallel: input.pipelineParallel,
    nodeIpPattern: input.nodeIpPattern,
    nodeIpStart: input.nodeIpStart,
    nodeIps: input.nodeIps,
  };
  local p = parallel.plan(parallelConfig);
  local checks = parallel.validate(parallelConfig, p, {
    weightsGiB: model.weightsGiB,
    vramFloorGiB: model.vramFloorGiB,
  });
  local expertParallel =
    input.expertParallel && std.type(p.tensorParallel) == 'number' && p.tensorParallel > 1;

  {
    tensorParallel: p.tensorParallel,
    pipelineParallel: p.pipelineParallel,
    expertParallel: expertParallel,
    errors: checks.errors,
    warnings: checks.warnings,
  };

local networkPlan(input, ws) =
  local ips = parallel.nodeIps({
    nodes: input.nodes,
    nodeIps: input.nodeIps,
    nodeIpPattern: input.nodeIpPattern,
    nodeIpStart: input.nodeIpStart,
  });

  local errors =
    (if std.type(input.nodeIps) != 'array' then
       ['nodeIps 必须是数组']
     else []) +
    (if std.type(ips) == 'array' then
       std.flattenArrays([
         (if std.type(ip) != 'string' then ['nodeIps 每项必须是字符串'] else [])
         for ip in ips
       ])
     else []) +
    (if std.type(ips) == 'array' &&
        std.type(input.nodes) == 'number' &&
        std.length(ips) != input.nodes then
       ['nodeIps 数量必须等于 nodes：%d != %d' % [std.length(ips), input.nodes]]
     else []);

  local warnings =
    if ws.nodeCount > 1 && !input.dockerNetworkHost then
      ['多机模式建议 dockerNetworkHost=true（--network host），否则 Ray / NCCL 端口需要额外映射']
    else [];

  { nodeIps: ips, errors: errors, warnings: warnings };

local backendPlan(input, ws) =
  local backendInput = input.distributedBackend;
  local backend = if ws.nodeCount > 1 then backendInput else 'local';

  local errors =
    (if ws.nodeCount > 1 && backend != 'ray' && backend != 'mp' then
       ['distributedBackend 必须是 ray 或 mp（当前：%s）' % str(backendInput)]
     else []) +
    util.intInRange('rayPort', input.rayPort, 1, 65535) +
    util.intInRange('masterPort', input.masterPort, 1, 65535);

  {
    backend: backend,
    isRay: backend == 'ray',
    isMp: backend == 'mp',
    rayPort: if backend == 'ray' then input.rayPort else null,
    masterPort: if backend == 'mp' then input.masterPort else null,
    errors: errors,
  };

local featurePlan(input, rawInput, model) =
  local caps = model.capabilities;

  // speculative
  local specDefaults = getOr(model.features, 'speculativeDefaults', {});
  local spec = std.mergePatch(specDefaults, featureInput(input.speculative));
  local specEnabledRaw = getOr(spec, 'enabled', getOr(specDefaults, 'enabled', true));
  local specEnabled = asBool(specEnabledRaw, true);
  local specMethod = getOr(spec, 'method', getOr(specDefaults, 'method', null));
  local specNumTokens =
    getOr(spec, 'numSpeculativeTokens', getOr(specDefaults, 'numSpeculativeTokens', null));
  local specDraftSample =
    getOr(spec, 'draftSampleMethod', getOr(specDefaults, 'draftSampleMethod', null));
  local specRejectionSample =
    getOr(spec, 'rejectionSampleMethod', getOr(specDefaults, 'rejectionSampleMethod', null));
  local specAdaptiveRaw =
    getOr(spec, 'enableAdaptiveVerification', getOr(specDefaults, 'enableAdaptiveVerification', false));
  local specAdaptive = asBool(specAdaptiveRaw, false);
  local specModel = getOr(spec, 'model', getOr(specDefaults, 'model', null));

  local specConfig = {
                       method: specMethod,
                       num_speculative_tokens: specNumTokens,
                     }
                     + (if specDraftSample != null then { draft_sample_method: specDraftSample } else {})
                     + (if specRejectionSample != null then { rejection_sample_method: specRejectionSample } else {})
                     + (if specMethod == 'dspark' then { enable_adaptive_verification: specAdaptive } else {})
                     + (if specModel != null then { model: specModel } else {});

  local specErrors =
    util.boolError('speculative.enabled', specEnabledRaw) +
    (if specEnabled && (!isInt(specNumTokens) || specNumTokens < 1) then
       ['speculative.numSpeculativeTokens 必须是 >= 1 的整数（当前：%s）' % str(specNumTokens)]
     else []) +
    (if specEnabled && std.type(specMethod) != 'string' then
       ['speculative.method 必须是字符串']
     else []);

  // thinking / reasoning effort
  local thinkingRaw = rawInput.thinking;
  local effortRaw = rawInput.reasoningEffort;
  local effortAliases = getOr(model, 'reasoningEffortAliases', {
    low: 25,
    high: 50,
    xhigh: 75,
    max: 100,
  });
  local effortNone = std.type(effortRaw) == 'string' && effortRaw == 'none';
  local thinking = asBool(thinkingRaw, true) && !effortNone;

  local effortValue =
    if !thinking then
      'none'
    else if std.type(effortRaw) == 'number' then
      effortRaw
    else if std.type(effortRaw) == 'string' && std.objectHas(effortAliases, effortRaw) then
      effortAliases[effortRaw]
    else
      null;

  local thinkingErrors =
    util.boolError('thinking', thinkingRaw) +
    (if !thinking then
       []
     else if effortValue == null then
       ['reasoningEffort 必须是 1-100 的整数、low/high/xhigh/max 或 none（当前：%s）' % str(effortRaw)]
     else if std.floor(effortValue) != effortValue || effortValue < 1 || effortValue > 100 then
       ['reasoningEffort 超出范围：%s' % str(effortRaw)]
     else []) +
    (if thinking && std.type(caps.reasoningParser) != 'string' then
       ['thinking 需要模型模板提供 model.capabilities.reasoningParser']
     else []);

  local chatTemplateKwargs =
    if thinking then
      { thinking: true, reasoning_effort: effortValue }
    else
      { thinking: false, reasoning_effort: 'none' };

  // tool calling
  local tool = std.mergePatch({
    enabled: true,
    parser: caps.toolParser,
  }, featureInput(input.toolCalling));
  local toolEnabledRaw = getOr(tool, 'enabled', true);
  local toolEnabled = asBool(toolEnabledRaw, true);
  local toolParser = getOr(tool, 'parser', caps.toolParser);

  local toolErrors =
    util.boolError('toolCalling.enabled', toolEnabledRaw) +
    (if toolEnabled && std.type(toolParser) != 'string' then
       ['toolCalling.parser 必须是字符串']
     else []);

  // multimodal
  local mm = std.mergePatch({
    enabled: false,
    mmEncoderTpMode: input.mmEncoderTpMode,
  }, featureInput(input.multimodal));
  local mmEnabledRaw = getOr(mm, 'enabled', false);
  local mmEnabled = asBool(mmEnabledRaw, false);
  local mmMode = getOr(mm, 'mmEncoderTpMode', input.mmEncoderTpMode);

  local mmErrors =
    util.boolError('multimodal.enabled', mmEnabledRaw) +
    (if mmEnabled && std.type(mmMode) != 'string' then
       ['mmEncoderTpMode 必须是字符串']
     else []) +
    (if mmEnabled &&
        std.type(mmMode) == 'string' &&
        mmMode != 'weights' &&
        mmMode != 'data' then
       ['mmEncoderTpMode 必须是 weights 或 data（当前：%s）' % str(mmMode)]
     else []) +
    (if mmEnabled && !asBool(caps.supportsMultimodal, false) then
       ['模板不支持 multimodal（model.capabilities.supportsMultimodal=false）']
     else []);

  {
    chatTemplateKwargs: chatTemplateKwargs,
    speculative: {
      enabled: specEnabled,
      config: specConfig,
    },
    thinking: {
      enabled: thinking,
      parser: if thinking then getOr(caps, 'reasoningParser', null) else null,
    },
    toolCalling: {
      enabled: toolEnabled,
      parser: toolParser,
    },
    multimodal: {
      enabled: mmEnabled,
      textOnly: !mmEnabled,
      encoderTpMode: mmMode,
    },
    errors: specErrors + thinkingErrors + toolErrors + mmErrors,
  };

local containerPlan(input, model, launch) =
  local extraEnv = input.extraEnv;
  local extraMounts = input.extraMounts;
  local envInput = if std.type(extraEnv) == 'object' then extraEnv else {};
  local envBase = std.mergePatch(
    getOr(launch, 'environment', {}),
    getOr(model.runtime, 'environment', {})
  );
  local env = std.mergePatch(envBase, envInput)
              + (if input.hfHubOffline then { HF_HUB_OFFLINE: '1' } else {});

  local modelMounts =
    if input.modelHostPath != null && input.modelPath != null then [{
      hostPath: input.modelHostPath,
      containerPath: input.modelPath,
      readOnly: true,
    }] else [];
  local mounts =
    modelMounts + (if std.type(extraMounts) == 'array' then extraMounts else []);

  {
    environment: {
      [k]: str(env[k])
      for k in std.objectFields(env)
      if env[k] != null
    },
    mounts: [
      {
        host_path: m.hostPath,
        container_path: m.containerPath,
        read_only: std.get(m, 'readOnly', true) != false,
      }
      for m in mounts
      if std.type(m) == 'object' &&
         std.objectHas(m, 'hostPath') &&
         std.objectHas(m, 'containerPath')
    ],
  };

// ---------------------------------------------------------------------------
// 输入校验（与旧 params 完全同序同文案）
// ---------------------------------------------------------------------------

local coreErrors(input, rawInput) =
  util.intInRange('port', input.port, 1, 65535) +
  util.intAtLeast('modelLayers', input.modelLayers, 1) +
  util.numberAtLeast('gpuMemoryGiB', input.gpuMemoryGiB, 1) +
  util.intAtLeast('maxModelLen', input.maxModelLen, 1) +
  util.intAtLeast('maxNumBatchedTokens', input.maxNumBatchedTokens, 1) +
  util.intAtLeast('maxCudagraphCaptureSize', input.maxCudagraphCaptureSize, 1) +
  (if std.type(input.gpuMemoryUtilization) != 'number' ||
      input.gpuMemoryUtilization <= 0 ||
      input.gpuMemoryUtilization > 1 then
     ['gpuMemoryUtilization 必须在 (0, 1] 范围内（当前：%s）' % str(input.gpuMemoryUtilization)]
   else []) +
  (if input.maxNumSeqs != null then util.intAtLeast('maxNumSeqs', input.maxNumSeqs, 1) else []) +
  util.boolError('expertParallel', rawInput.expertParallel) +
  util.boolError('enforceEager', rawInput.enforceEager) +
  util.boolError('disableUvicornAccessLog', rawInput.disableUvicornAccessLog) +
  util.boolError('dockerNetworkHost', rawInput.dockerNetworkHost) +
  util.boolError('hfHubOffline', rawInput.hfHubOffline);

local extraErrors(input) =
  (if std.type(input.extraEnv) != 'object' then ['extraEnv 必须是对象'] else []) +
  (if std.type(input.extraMounts) != 'array' then ['extraMounts 必须是数组'] else []) +
  (if std.type(input.extraDockerArgs) != 'array' then ['extraDockerArgs 必须是数组'] else []) +
  (if std.type(input.extraArgs) != 'array' then ['extraArgs 必须是数组'] else []) +
  (if std.type(input.extraDockerArgs) == 'array' then
     std.flattenArrays([
       (if std.type(a) != 'string' then ['extraDockerArgs 每项必须是字符串'] else [])
       for a in input.extraDockerArgs
     ])
   else []) +
  (if std.type(input.extraArgs) == 'array' then
     std.flattenArrays([
       (if std.type(a) != 'string' then ['extraArgs 每项必须是字符串'] else [])
       for a in input.extraArgs
     ])
   else []) +
  (if std.type(input.extraMounts) == 'array' then
     std.flattenArrays([
       (if std.type(m) != 'object' ||
           !std.objectHas(m, 'hostPath') ||
           !std.objectHas(m, 'containerPath') then
          ['extraMounts 每项必须包含 hostPath 与 containerPath']
        else [])
       for m in input.extraMounts
     ])
   else []) +
  (if input.modelHostPath != null && input.modelPath == null then
     ['设置了 modelHostPath 时必须同时设置 modelPath（容器内路径）']
   else []);

// ---------------------------------------------------------------------------
// 公开 API
// ---------------------------------------------------------------------------

local contextImpl(args) =
  local model = args.model;
  local hardware = args.hardware;
  local launch = args.launch;
  local config = if std.objectHas(args, 'config') then args.config else {};
  local ri = resolveInput(model, hardware, launch, config);
  local input = ri.input;
  local rawInput = ri.rawInput;
  local ws = worldSize(input, config);
  local p = parallelPlan(input, ws, model);
  local net = networkPlan(input, ws);
  local be = backendPlan(input, ws);
  local ft = featurePlan(input, rawInput, model);
  local ct = containerPlan(input, model, launch);

  {
    input: input,
    rawInput: rawInput,
    model: model,
    hardware: hardware,
    launch: launch,
    automation: {
      worldSize: ws,
      parallel: p,
      network: net,
      backend: be,
      features: ft,
      container: ct,
    },
    errors:
      ri.configErrors +
      p.errors +
      be.errors +
      net.errors +
      ft.errors +
      coreErrors(input, rawInput) +
      ws.totalGpusErrors +
      ws.conflictErrors +
      extraErrors(input),
    warnings: p.warnings + net.warnings,
  };

{
  defaults(args):: defaultsFor(args.model, args.hardware, args.launch),

  context(args):: contextImpl(args),

  params(args):: {
    apiVersion: apiVersion,
    scenario: args.ctx.input.scenario,
    serve: args.serve,
    deployment: args.deployment,
    container: args.container,
    extras: args.extras,
    warnings: args.ctx.warnings,
    errors: args.ctx.errors,
  },

  parallelServeParams(ctx)::
    if ctx.automation.parallel.expertParallel then
      { enable_expert_parallel: true }
    else {},

  featuresServeParams(ctx)::
    local f = ctx.automation.features;
    (if f.speculative.enabled then
       { speculative_config: f.speculative.config }
     else {}) +
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
       { language_model_only: true }),

  inputServeParams(ctx)::
    (if ctx.input.apiKey != null then { api_key: ctx.input.apiKey } else {}) +
    (if ctx.input.maxNumSeqs != null then { max_num_seqs: ctx.input.maxNumSeqs } else {}) +
    (if ctx.input.disableUvicornAccessLog then { disable_uvicorn_access_log: true } else {}) +
    (if ctx.input.enforceEager then { enforce_eager: true } else {}),

  backendPortParams(ctx)::
    (if ctx.automation.backend.isRay then { ray_port: ctx.input.rayPort } else {}) +
    (if ctx.automation.backend.isMp then { master_port: ctx.input.masterPort } else {}),
}
