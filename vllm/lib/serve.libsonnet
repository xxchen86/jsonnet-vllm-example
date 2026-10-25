// DeepSeek-V4.1-Flash 的 vLLM 启动参数生成器。
//
// 官方 recipe：
//   https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash
//
// 设计目标：
//   1. 用一份 JSON 参数描述「机器数、每机卡数、功能开关」；
//   2. 自动推导 TP / PP，并校验 TP × PP == 总卡数；
//   3. 多机时生成 Ray 或 mp 两种后端所需的逐机命令；
//   4. 把 thinking / tool calling / 投机推理 / 多模态开关映射为 vLLM 参数。

local parallel = import 'parallel.libsonnet';

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

local getOr(obj, field, fallback) =
  if std.objectHas(obj, field) && obj[field] != null then obj[field] else fallback;

local asBool(value, fallback) =
  if std.type(value) == 'boolean' then value else fallback;

local str(value) = std.toString(value);

local isInt(value) =
  std.type(value) == 'number' && std.floor(value) == value;

local intAtLeast(field, value, min) =
  if !isInt(value) || value < min then
    ['%s 必须是 >= %d 的整数（当前：%s，类型：%s）' % [field, min, str(value), std.type(value)]]
  else [];

local intInRange(field, value, min, max) =
  if !isInt(value) || value < min || value > max then
    ['%s 必须是 %d-%d 之间的整数（当前：%s，类型：%s）' % [field, min, max, str(value), std.type(value)]]
  else [];

local numberAtLeast(field, value, min) =
  if std.type(value) != 'number' || value < min then
    ['%s 必须是 >= %s 的数字（当前：%s，类型：%s）' % [field, str(min), str(value), std.type(value)]]
  else [];

local boolError(field, value) =
  if std.type(value) != 'boolean' then
    ['%s 必须是布尔值（当前：%s，类型：%s）' % [field, str(value), std.type(value)]]
  else [];

// 布尔开关 / 对象两种写法都接受：
//   speculative: true
//   speculative: { enabled: true, numSpeculativeTokens: 3 }
local featureInput(value) =
  if value == null then {}
  else if std.type(value) == 'object' then value
  else { enabled: value };

// ---------------------------------------------------------------------------
// shell 命令渲染
// ---------------------------------------------------------------------------

local safeChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=@%+,-';
local isSafeChar(c) = std.length(std.find(c, std.stringChars(safeChars))) > 0;
local isSafe(s) = std.foldl(function(acc, c) acc && isSafeChar(c), std.stringChars(s), true);

local shellQuote(s) =
  if s == '' then
    "''"
  else if isSafe(s) then
    s
  else
    "'" + std.strReplace(s, "'", "'" + '\\' + "'" + "'") + "'";

local joinArgs(args) = std.join(' ', std.map(shellQuote, args));

// 避免 0.9 被打印成 0.90000000000000002；整数保持原样。
local numStr(value) =
  if std.type(value) == 'number' && std.floor(value) != value then
    std.format('%.10g', value)
  else
    std.toString(value);

local flag(name, value) = [name, numStr(value)];
local flagOnly(name) = [name];

// ---------------------------------------------------------------------------
// 默认值（与官方 recipe 对齐）
// ---------------------------------------------------------------------------

local defaults = {
  scenario: 'custom',

  // 模型与镜像
  model: 'deepseek-ai/DeepSeek-V4.1-Flash',
  servedModelName: 'deepseek-ai/DeepSeek-V4.1-Flash',
  modelPath: null,  // 容器内模型路径；为 null 时直接使用 HF model id
  modelHostPath: null,  // 宿主机模型目录；与 modelPath 同时设置时自动挂载
  image: 'vllm/vllm-openai:deepseekv41-flash-0909',

  // HTTP 服务
  host: '0.0.0.0',
  port: 8000,
  apiKey: null,

  // 机器与并行
  nodes: 1,
  totalGpus: null,  // 可选：总卡数；设置后按 nodes 推导 gpusPerNode
  gpusPerNode: 8,
  gpuMemoryGiB: 141,  // H200=141，H100=80，B200/GB200=192
  modelLayers: 40,
  parallelMode: 'auto',  // auto | tp | tp-pp
  tensorParallel: null,  // 显式覆盖
  pipelineParallel: null,  // 显式覆盖
  expertParallel: true,
  distributedBackend: 'ray',  // ray | mp（仅多机生效）

  // vLLM 性能参数（官方 recipe）
  maxModelLen: 1048576,
  maxNumBatchedTokens: 16384,
  maxCudagraphCaptureSize: 1024,
  gpuMemoryUtilization: 0.9,
  maxNumSeqs: null,
  enforceEager: false,
  disableUvicornAccessLog: true,

  // 功能开关
  speculative: true,
  thinking: true,
  reasoningEffort: 50,  // 1-100，或 low / high / xhigh / max / none
  toolCalling: true,
  multimodal: false,
  mmEncoderTpMode: 'data',

  // 网络与容器
  nodeIpPattern: '10.0.0.%d',
  nodeIpStart: 10,
  nodeIps: [],
  rayPort: 6379,
  masterPort: 29501,
  containerNamePrefix: 'dsv41',
  dockerShmSize: '32g',
  dockerNetworkHost: true,
  hfHubOffline: false,

  // 逃生舱
  extraEnv: {},
  extraMounts: [],
  extraDockerArgs: [],
  extraArgs: [],
};

{
  defaults:: defaults,

  render(userConfig)::
    local cfg =
      if std.type(userConfig) == 'object' then std.mergePatch(defaults, userConfig)
      else error 'config 必须是对象';

    // -----------------------------------------------------------------------
    // 基本输入
    // -----------------------------------------------------------------------
    local scenario = getOr(cfg, 'scenario', defaults.scenario);
    local model = getOr(cfg, 'model', defaults.model);
    local servedName = getOr(cfg, 'servedModelName', model);
    local modelPath = getOr(cfg, 'modelPath', null);
    local modelHostPath = getOr(cfg, 'modelHostPath', null);
    local image = getOr(cfg, 'image', defaults.image);
    local host = getOr(cfg, 'host', defaults.host);
    local port = getOr(cfg, 'port', defaults.port);
    local apiKey = getOr(cfg, 'apiKey', null);

    local nodes = getOr(cfg, 'nodes', defaults.nodes);
    // 结构生成使用 nodeCount；非法 nodes 交给 validate 报错，避免先触发数组越界。
    local nodeCount = if isInt(nodes) && nodes >= 1 then nodes else 0;

    // 卡数支持两种外部输入：totalGpus（总卡数）或 gpusPerNode（每机卡数）。
    // totalGpus 优先，但必须能被 nodes 整除；两者冲突时直接报错。
    local totalGpus = getOr(cfg, 'totalGpus', null);
    local gpusPerNodeInput = getOr(cfg, 'gpusPerNode', defaults.gpusPerNode);
    local explicitGpusPerNode =
      if std.type(userConfig) == 'object' &&
         std.objectHas(userConfig, 'gpusPerNode') &&
         userConfig.gpusPerNode != null then userConfig.gpusPerNode
      else null;
    local totalGpusValid =
      std.type(totalGpus) == 'number' && isInt(totalGpus) && totalGpus >= 1;
    local totalGpusDivisible =
      totalGpusValid && isInt(nodes) && nodes >= 1 && totalGpus % nodes == 0;
    local derivedGpusPerNode =
      if totalGpusDivisible then totalGpus / nodes else null;
    local gpusPerNode =
      if derivedGpusPerNode != null then derivedGpusPerNode else gpusPerNodeInput;
    local gpuMemoryGiB = getOr(cfg, 'gpuMemoryGiB', defaults.gpuMemoryGiB);
    local modelLayers = getOr(cfg, 'modelLayers', defaults.modelLayers);
    local parallelMode = getOr(cfg, 'parallelMode', defaults.parallelMode);
    local expertParallelRaw = getOr(cfg, 'expertParallel', defaults.expertParallel);
    local expertParallel = asBool(expertParallelRaw, true);
    local backendInput = getOr(cfg, 'distributedBackend', defaults.distributedBackend);
    local backend = if nodeCount > 1 then backendInput else 'local';

    local maxModelLen = getOr(cfg, 'maxModelLen', defaults.maxModelLen);
    local maxNumBatchedTokens = getOr(cfg, 'maxNumBatchedTokens', defaults.maxNumBatchedTokens);
    local maxCudagraphCaptureSize = getOr(cfg, 'maxCudagraphCaptureSize', defaults.maxCudagraphCaptureSize);
    local gpuMemoryUtilization = getOr(cfg, 'gpuMemoryUtilization', defaults.gpuMemoryUtilization);
    local maxNumSeqs = getOr(cfg, 'maxNumSeqs', null);
    local enforceEagerRaw = getOr(cfg, 'enforceEager', defaults.enforceEager);
    local enforceEager = asBool(enforceEagerRaw, false);
    local disableAccessLogRaw = getOr(cfg, 'disableUvicornAccessLog', defaults.disableUvicornAccessLog);
    local disableAccessLog = asBool(disableAccessLogRaw, true);

    // -----------------------------------------------------------------------
    // 并行推导
    // -----------------------------------------------------------------------
    local parallelConfig = {
      nodes: nodes,
      gpusPerNode: gpusPerNode,
      gpuMemoryGiB: gpuMemoryGiB,
      modelLayers: modelLayers,
      parallelMode: parallelMode,
      tensorParallel: getOr(cfg, 'tensorParallel', null),
      pipelineParallel: getOr(cfg, 'pipelineParallel', null),
      nodeIpPattern: getOr(cfg, 'nodeIpPattern', defaults.nodeIpPattern),
      nodeIpStart: getOr(cfg, 'nodeIpStart', defaults.nodeIpStart),
      nodeIps: getOr(cfg, 'nodeIps', defaults.nodeIps),
    };

    local p = parallel.plan(parallelConfig);
    local checks = parallel.validate(parallelConfig, p);
    local ips = parallel.nodeIps(parallelConfig);

    // -----------------------------------------------------------------------
    // 投机解码（DSpark）
    // -----------------------------------------------------------------------
    local spec = std.mergePatch({
      enabled: true,
      method: 'dspark',
      numSpeculativeTokens: 5,
      draftSampleMethod: 'probabilistic',
      rejectionSampleMethod: 'block',
      enableAdaptiveVerification: false,
    }, featureInput(getOr(cfg, 'speculative', defaults.speculative)));

    local specEnabledRaw = getOr(spec, 'enabled', true);
    local specEnabled = asBool(specEnabledRaw, true);
    local specMethod = getOr(spec, 'method', 'dspark');
    local specNumTokens = getOr(spec, 'numSpeculativeTokens', 5);
    local specDraftSample = getOr(spec, 'draftSampleMethod', 'probabilistic');
    local specRejectionSample = getOr(spec, 'rejectionSampleMethod', 'block');
    local specAdaptiveRaw = getOr(spec, 'enableAdaptiveVerification', false);
    local specAdaptive = asBool(specAdaptiveRaw, false);
    local specModel = getOr(spec, 'model', null);

    local specConfig =
      {
        method: specMethod,
        num_speculative_tokens: specNumTokens,
      }
      + (if specDraftSample != null then { draft_sample_method: specDraftSample } else {})
      + (if specRejectionSample != null then { rejection_sample_method: specRejectionSample } else {})
      + (if specMethod == 'dspark' then { enable_adaptive_verification: specAdaptive } else {})
      + (if specModel != null then { model: specModel } else {});

    local specConfigJson = std.manifestJsonMinified(specConfig);

    // -----------------------------------------------------------------------
    // thinking / reasoning effort
    // -----------------------------------------------------------------------
    local thinkingRaw = getOr(cfg, 'thinking', defaults.thinking);
    local effortRaw = getOr(cfg, 'reasoningEffort', defaults.reasoningEffort);
    local effortAliases = { low: 25, high: 50, xhigh: 75, max: 100 };
    // reasoningEffort="none" 与 thinking=false 等价。
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
      boolError('thinking', thinkingRaw) +
      (if !thinking then
         []
       else if effortValue == null then
         ['reasoningEffort 必须是 1-100 的整数、low/high/xhigh/max 或 none（当前：%s）' % str(effortRaw)]
       else if std.floor(effortValue) != effortValue || effortValue < 1 || effortValue > 100 then
         ['reasoningEffort 超出范围：%s' % str(effortRaw)]
       else []);

    local chatTemplateKwargs =
      if thinking then
        { thinking: true, reasoning_effort: effortValue }
      else
        { thinking: false, reasoning_effort: 'none' };

    local chatTemplateKwargsJson = std.manifestJsonMinified(chatTemplateKwargs);

    // -----------------------------------------------------------------------
    // tool calling / 多模态
    // -----------------------------------------------------------------------
    local tool = std.mergePatch({
      enabled: true,
      parser: 'deepseek_v41',
    }, featureInput(getOr(cfg, 'toolCalling', defaults.toolCalling)));

    local toolEnabledRaw = getOr(tool, 'enabled', true);
    local toolEnabled = asBool(toolEnabledRaw, true);
    local toolParser = getOr(tool, 'parser', 'deepseek_v41');

    local mm = std.mergePatch({
      enabled: false,
      mmEncoderTpMode: getOr(cfg, 'mmEncoderTpMode', defaults.mmEncoderTpMode),
    }, featureInput(getOr(cfg, 'multimodal', defaults.multimodal)));

    local mmEnabledRaw = getOr(mm, 'enabled', false);
    local mmEnabled = asBool(mmEnabledRaw, false);
    local mmMode = getOr(mm, 'mmEncoderTpMode', getOr(cfg, 'mmEncoderTpMode', defaults.mmEncoderTpMode));

    // -----------------------------------------------------------------------
    // 网络 / 容器 / 逃生舱
    // -----------------------------------------------------------------------
    local rayPort = getOr(cfg, 'rayPort', defaults.rayPort);
    local masterPort = getOr(cfg, 'masterPort', defaults.masterPort);
    local containerPrefix = getOr(cfg, 'containerNamePrefix', defaults.containerNamePrefix);
    local dockerShmSize = getOr(cfg, 'dockerShmSize', defaults.dockerShmSize);
    local networkHostRaw = getOr(cfg, 'dockerNetworkHost', defaults.dockerNetworkHost);
    local networkHost = asBool(networkHostRaw, true);
    local hfHubOfflineRaw = getOr(cfg, 'hfHubOffline', defaults.hfHubOffline);
    local hfHubOffline = asBool(hfHubOfflineRaw, false);

    local extraEnv = getOr(cfg, 'extraEnv', defaults.extraEnv);
    local extraMounts = getOr(cfg, 'extraMounts', defaults.extraMounts);
    local extraDockerArgs = getOr(cfg, 'extraDockerArgs', defaults.extraDockerArgs);
    local extraArgs = getOr(cfg, 'extraArgs', defaults.extraArgs);

    local envInput = if std.type(extraEnv) == 'object' then extraEnv else {};
    local env =
      std.mergePatch({
        VLLM_ENGINE_READY_TIMEOUT_S: '3600',
        VLLM_USE_RUST_FRONTEND: '1',
      }, envInput)
      + (if hfHubOffline then { HF_HUB_OFFLINE: '1' } else {});

    local modelTarget = if modelPath != null then modelPath else model;
    local modelMounts =
      if modelHostPath != null && modelPath != null then [{
        hostPath: modelHostPath,
        containerPath: modelPath,
        readOnly: true,
      }] else [];

    local mounts =
      modelMounts + (if std.type(extraMounts) == 'array' then extraMounts else []);

    // -----------------------------------------------------------------------
    // vLLM 参数
    // -----------------------------------------------------------------------
    local expertEnabled =
      expertParallel && std.type(p.tensorParallel) == 'number' && p.tensorParallel > 1;

    local prePairs =
      [
        flag('--served-model-name', servedName),
        flag('--host', host),
        flag('--port', port),
      ]
      + (if apiKey != null then [flag('--api-key', apiKey)] else [])
      + [
        flag('--tokenizer-mode', 'deepseek_v41'),
        flag('--tensor-parallel-size', p.tensorParallel),
      ]
      + (if std.type(p.pipelineParallel) == 'number' && p.pipelineParallel > 1 then
           [flag('--pipeline-parallel-size', p.pipelineParallel)]
         else [])
      + (if expertEnabled then [flagOnly('--enable-expert-parallel')] else []);

    local postPairs =
      [
        flag('--max-model-len', maxModelLen),
        flag('--max-num-batched-tokens', maxNumBatchedTokens),
        flag('--max-cudagraph-capture-size', maxCudagraphCaptureSize),
        flag('--gpu-memory-utilization', gpuMemoryUtilization),
      ]
      + (if maxNumSeqs != null then [flag('--max-num-seqs', maxNumSeqs)] else [])
      + (if specEnabled then [flag('--speculative-config', specConfigJson)] else [])
      + (if thinking then [flag('--reasoning-parser', 'deepseek_v41')] else [])
      + [flag('--default-chat-template-kwargs', chatTemplateKwargsJson)]
      + (if toolEnabled then [
           flag('--tool-call-parser', toolParser),
           flagOnly('--enable-auto-tool-choice'),
         ] else [])
      + (if mmEnabled then
           [flag('--mm-encoder-tp-mode', mmMode)]
         else
           [flagOnly('--language-model-only')])
      + (if disableAccessLog then [flagOnly('--disable-uvicorn-access-log')] else [])
      + (if enforceEager then [flagOnly('--enforce-eager')] else [])
      + [[a] for a in (if std.type(extraArgs) == 'array' then extraArgs else [])];

    local distributedPairs(rank) =
      if nodeCount <= 1 then
        []
      else if backend == 'ray' then
        [flag('--distributed-executor-backend', 'ray')]
      else
        [
          flag('--distributed-executor-backend', 'mp'),
          flag('--nnodes', nodes),
          flag('--node-rank', rank),
          flag('--master-addr', ips[0]),
          flag('--master-port', masterPort),
        ]
        + (if rank > 0 then [flagOnly('--headless')] else []);

    local argvFor(rank) =
      ['vllm', 'serve', modelTarget]
      + std.flattenArrays(prePairs)
      + std.flattenArrays(distributedPairs(rank))
      + std.flattenArrays(postPairs);

    // -----------------------------------------------------------------------
    // 逐机 Docker 命令
    // -----------------------------------------------------------------------
    local dockerFor(rank, isHead, nodeEnv, inner) =
      local envPairs = [
        { key: k, value: str(nodeEnv[k]) }
        for k in std.objectFields(nodeEnv)
        if nodeEnv[k] != null
      ];
      local envArgs = std.flattenArrays([['-e', e.key + '=' + e.value] for e in envPairs]);
      local mountArgs = std.flattenArrays([
        ['-v', m.hostPath + ':' + m.containerPath + (if std.get(m, 'readOnly', true) == false then '' else ':ro')]
        for m in mounts
        if std.type(m) == 'object' && std.objectHas(m, 'hostPath') && std.objectHas(m, 'containerPath')
      ]);
      local portArgs =
        if networkHost then
          []
        else if isHead then
          if nodeCount <= 1 then
            ['-p', str(port) + ':' + str(port)]
          else if backend == 'ray' then
            ['-p', str(port) + ':' + str(port), '-p', str(rayPort) + ':' + str(rayPort)]
          else
            ['-p', str(port) + ':' + str(port), '-p', str(masterPort) + ':' + str(masterPort)]
        else
          [];
      local dockerArgv =
        [
          'docker',
          'run',
          '--name',
          containerPrefix + '-node-' + str(rank),
          '--gpus',
          'all',
          '--ipc',
          'host',
          '--shm-size',
          dockerShmSize,
        ]
        + (if networkHost then ['--network', 'host'] else portArgs)
        + envArgs
        + mountArgs
        + (if std.type(extraDockerArgs) == 'array' then extraDockerArgs else [])
        + ['--entrypoint', 'bash', image, '-c', inner];
      {
        argv: dockerArgv,
        command: joinArgs(dockerArgv),
      };

    local mkNode(rank) =
      local ip = ips[rank];
      local isHead = rank == 0;
      local role =
        if nodeCount <= 1 then 'server'
        else if isHead then 'head'
        else 'worker';

      local nodeEnv =
        env + (if nodeCount > 1 then { VLLM_HOST_IP: ip } else {});

      local serveArgv = argvFor(rank);

      local rayHeadArgv = [
        'ray',
        'start',
        '--head',
        '--port=' + str(rayPort),
        '--node-ip-address=' + ip,
        '--num-gpus=' + str(gpusPerNode),
        '--disable-usage-stats',
      ];
      local rayWorkerArgv = [
        'ray',
        'start',
        '--address=' + ips[0] + ':' + str(rayPort),
        '--node-ip-address=' + ip,
        '--num-gpus=' + str(gpusPerNode),
        '--block',
        '--disable-usage-stats',
      ];

      local inner =
        if nodeCount <= 1 then
          joinArgs(serveArgv)
        else if backend == 'mp' then
          joinArgs(serveArgv)
        else if isHead then
          joinArgs(rayHeadArgv) + ' && ' + joinArgs(serveArgv)
        else
          joinArgs(rayWorkerArgv);

      local docker = dockerFor(rank, isHead, nodeEnv, inner);

      {
        rank: rank,
        role: role,
        ip: ip,
        env: nodeEnv,
        innerCommand: inner,
        serve:
          if backend == 'ray' && !isHead then
            null
          else {
            argv: serveArgv,
            command: joinArgs(serveArgv),
          },
        ray:
          if nodeCount > 1 && backend == 'ray' then {
            argv: if isHead then rayHeadArgv else rayWorkerArgv,
            command: joinArgs(if isHead then rayHeadArgv else rayWorkerArgv),
          } else null,
        docker: docker,
        command: docker.command,
      };

    local nodeObjects = [mkNode(i) for i in std.range(0, nodeCount - 1)];

    // -----------------------------------------------------------------------
    // 校验
    // -----------------------------------------------------------------------
    local specErrors =
      boolError('speculative.enabled', specEnabledRaw) +
      (if specEnabled && (!isInt(specNumTokens) || specNumTokens < 1) then
         ['speculative.numSpeculativeTokens 必须是 >= 1 的整数（当前：%s）' % str(specNumTokens)]
       else []) +
      (if specEnabled && std.type(specMethod) != 'string' then
         ['speculative.method 必须是字符串']
       else []);

    local toolErrors =
      boolError('toolCalling.enabled', toolEnabledRaw) +
      (if toolEnabled && std.type(toolParser) != 'string' then
         ['toolCalling.parser 必须是字符串']
       else []);

    local mmErrors =
      boolError('multimodal.enabled', mmEnabledRaw) +
      (if mmEnabled && std.type(mmMode) != 'string' then
         ['mmEncoderTpMode 必须是字符串']
       else []) +
      (if mmEnabled && std.type(mmMode) == 'string' && (mmMode != 'weights' && mmMode != 'data') then
         ['mmEncoderTpMode 必须是 weights 或 data（当前：%s）' % str(mmMode)]
       else []);

    local distributedErrors =
      (if nodeCount > 1 && backend != 'ray' && backend != 'mp' then
         ['distributedBackend 必须是 ray 或 mp（当前：%s）' % str(backendInput)]
       else []) +
      intInRange('rayPort', rayPort, 1, 65535) +
      intInRange('masterPort', masterPort, 1, 65535) +
      (if std.type(parallelConfig.nodeIps) != 'array' then
         ['nodeIps 必须是数组']
       else []) +
      (if std.type(ips) == 'array' then
         std.flattenArrays([
           (if std.type(ip) != 'string' then ['nodeIps 每项必须是字符串'] else [])
           for ip in ips
         ])
       else []) +
      (if std.type(ips) == 'array' && std.type(nodes) == 'number' && std.length(ips) != nodes then
         ['nodeIps 数量必须等于 nodes：%d != %d' % [std.length(ips), nodes]]
       else []);

    local coreErrors =
      intInRange('port', port, 1, 65535) +
      intAtLeast('modelLayers', modelLayers, 1) +
      numberAtLeast('gpuMemoryGiB', gpuMemoryGiB, 1) +
      intAtLeast('maxModelLen', maxModelLen, 1) +
      intAtLeast('maxNumBatchedTokens', maxNumBatchedTokens, 1) +
      intAtLeast('maxCudagraphCaptureSize', maxCudagraphCaptureSize, 1) +
      (if std.type(gpuMemoryUtilization) != 'number' ||
          gpuMemoryUtilization <= 0 ||
          gpuMemoryUtilization > 1 then
         ['gpuMemoryUtilization 必须在 (0, 1] 范围内（当前：%s）' % str(gpuMemoryUtilization)]
       else []) +
      (if maxNumSeqs != null then intAtLeast('maxNumSeqs', maxNumSeqs, 1) else []) +
      boolError('expertParallel', expertParallelRaw) +
      boolError('enforceEager', enforceEagerRaw) +
      boolError('disableUvicornAccessLog', disableAccessLogRaw) +
      boolError('dockerNetworkHost', networkHostRaw) +
      boolError('hfHubOffline', hfHubOfflineRaw);

    local extraErrors =
      (if std.type(extraEnv) != 'object' then ['extraEnv 必须是对象'] else []) +
      (if std.type(extraMounts) != 'array' then ['extraMounts 必须是数组'] else []) +
      (if std.type(extraDockerArgs) != 'array' then ['extraDockerArgs 必须是数组'] else []) +
      (if std.type(extraArgs) != 'array' then ['extraArgs 必须是数组'] else []) +
      (if std.type(extraDockerArgs) == 'array' then
         std.flattenArrays([
           (if std.type(a) != 'string' then ['extraDockerArgs 每项必须是字符串'] else [])
           for a in extraDockerArgs
         ])
       else []) +
      (if std.type(extraArgs) == 'array' then
         std.flattenArrays([
           (if std.type(a) != 'string' then ['extraArgs 每项必须是字符串'] else [])
           for a in extraArgs
         ])
       else []) +
      (if std.type(extraMounts) == 'array' then
         std.flattenArrays([
           (if std.type(m) != 'object' ||
               !std.objectHas(m, 'hostPath') ||
               !std.objectHas(m, 'containerPath') then
              ['extraMounts 每项必须包含 hostPath 与 containerPath']
            else [])
           for m in extraMounts
         ])
       else []) +
      (if modelHostPath != null && modelPath == null then
         ['设置了 modelHostPath 时必须同时设置 modelPath（容器内路径）']
       else []);

    local totalGpusErrors =
      if totalGpus == null then
        []
      else if !totalGpusValid then
        ['totalGpus 必须是 >= 1 的整数（当前：%s，类型：%s）' % [str(totalGpus), std.type(totalGpus)]]
      else if !isInt(nodes) || nodes < 1 then
        []  // nodes 自己会报错
      else if totalGpus % nodes != 0 then
        ['totalGpus 必须能被 nodes 整除：%d / %d 不是整数' % [totalGpus, nodes]]
      else [];

    local totalGpusConflictErrors =
      if derivedGpusPerNode != null &&
         explicitGpusPerNode != null &&
         explicitGpusPerNode != derivedGpusPerNode then
        ['totalGpus=%d 推导出的 gpusPerNode=%d 与显式 gpusPerNode=%s 冲突' % [
          totalGpus,
          derivedGpusPerNode,
          str(explicitGpusPerNode),
        ]]
      else [];

    local errors =
      checks.errors +
      distributedErrors +
      specErrors +
      thinkingErrors +
      toolErrors +
      mmErrors +
      coreErrors +
      totalGpusErrors +
      totalGpusConflictErrors +
      extraErrors;

    local warnings =
      checks.warnings +
      (if nodeCount > 1 && !networkHost then
         ['多机模式建议 dockerNetworkHost=true（--network host），否则 Ray / NCCL 端口需要额外映射']
       else []);

    {
      assert std.length(errors) == 0 : std.join('; ', errors),

      apiVersion: 'vllm-recipe.jsonnet/v1',

      meta: {
        name: 'DeepSeek-V4.1-Flash vLLM launcher',
        recipe: 'https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash',
        requires: 'vLLM >= 0.31.0；镜像 vllm/vllm-openai:deepseekv41-flash-0909',
        notes: [
          'TP / PP 由 nodes × gpusPerNode 推导；也可只传 totalGpus，由 nodes 推导每机卡数。',
          '多机默认使用 Ray；distributedBackend="mp" 可切换为 vLLM 原生 --nnodes 模式。',
          'thinking 默认开启；reasoningEffort 支持 1-100、low/high/xhigh/max 或 none。',
        ],
      },

      scenario: scenario,

      input: {
        nodes: nodes,
        totalGpus: totalGpus,
        gpusPerNode: gpusPerNode,
        parallelMode: parallelMode,
        tensorParallel: p.tensorParallel,
        pipelineParallel: p.pipelineParallel,
        distributedBackend: backend,
        speculative: specEnabled,
        speculativeMethod: specMethod,
        thinking: thinking,
        reasoningEffort: effortValue,
        toolCalling: toolEnabled,
        multimodal: mmEnabled,
      },

      parallel: {
        nodes: nodes,
        gpusPerNode: gpusPerNode,
        worldSize: p.worldSize,
        tensorParallel: p.tensorParallel,
        pipelineParallel: p.pipelineParallel,
        expertParallel: expertEnabled,
        mode: parallelMode,
        description: 'TP%d × PP%d（%d 机 × %d 卡 = %d 卡）' % [
          p.tensorParallel,
          p.pipelineParallel,
          nodes,
          gpusPerNode,
          p.worldSize,
        ],
      },

      distributed: {
        backend: backend,
        multiNode: nodeCount > 1,
        nodeIps: ips,
        headAddress: if nodeCount > 1 then ips[0] else null,
        rayPort: if backend == 'ray' then rayPort else null,
        masterPort: if backend == 'mp' then masterPort else null,
      },

      features: {
        speculative: {
          enabled: specEnabled,
          method: specMethod,
          numSpeculativeTokens: specNumTokens,
          config: if specEnabled then specConfig else null,
        },
        thinking: {
          enabled: thinking,
          reasoningEffort: effortValue,
          defaultChatTemplateKwargs: chatTemplateKwargs,
        },
        toolCalling: {
          enabled: toolEnabled,
          parser: toolParser,
        },
        multimodal: {
          enabled: mmEnabled,
          languageModelOnly: !mmEnabled,
          mmEncoderTpMode: if mmEnabled then mmMode else null,
        },
      },

      environment: env,

      serve: {
        model: modelTarget,
        servedModelName: servedName,
        argv: argvFor(0),
        command: joinArgs(argvFor(0)),
      },

      deployment: {
        mode:
          if nodeCount <= 1 then 'single-node'
          else if backend == 'ray' then 'ray-multi-node'
          else 'mp-multi-node',
        nodes: nodeObjects,
        commands: [n.command for n in nodeObjects],
      },

      warnings: warnings,
    },
}
