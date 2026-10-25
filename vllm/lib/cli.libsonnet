// DeepSeek-V4.1-Flash CLI 渲染器：vLLM 原生参数产物 -> argv / shell / Docker / Ray / mp 命令。
//
// 本模块只消费 vllm-params/v1 产物，不 import 阶段 1 的 launch / launch-helpers，
// 不做默认值、合并或 TP/PP 推导。参数产物缺失必填字段时直接报错。

local paramsApiVersion = 'vllm-params/v1';
local cliApiVersion = 'vllm-cli/v1';

// ---------------------------------------------------------------------------
// 类型 / schema 校验
// ---------------------------------------------------------------------------

local isObj(v) = std.type(v) == 'object';
local isArr(v) = std.type(v) == 'array';
local isStr(v) = std.type(v) == 'string';
local isBool(v) = std.type(v) == 'boolean';
local isNum(v) = std.type(v) == 'number';
local isInt(v) = isNum(v) && std.floor(v) == v;

local isIntAtLeast(v, min) = isInt(v) && v >= min;
local isPort(v) = isInt(v) && v >= 1 && v <= 65535;
local isGpuMem(v) = isNum(v) && v > 0 && v <= 1;
local isBackend(v) = isStr(v) && std.length(std.find(v, ['local', 'ray', 'mp'])) > 0;
local isMmMode(v) = isStr(v) && std.length(std.find(v, ['data', 'weights'])) > 0;

local has(obj, key) = isObj(obj) && std.objectHas(obj, key);
local show(v) =
  if isObj(v) || isArr(v) then std.manifestJsonMinified(v)
  else std.toString(v);
local str(v) = std.toString(v);

local req(obj, key, pred, label) =
  if !has(obj, key) then
    ['%s 缺少必填字段 %s' % [label, key]]
  else if !pred(obj[key]) then
    ['%s.%s 不合法（当前：%s）' % [label, key, show(obj[key])]]
  else [];

local opt(obj, key, pred, label) =
  if has(obj, key) then
    (if !pred(obj[key]) then
       ['%s.%s 不合法（当前：%s）' % [label, key, show(obj[key])]]
     else [])
  else [];

local stringArrayErrors(arr, label) =
  if isArr(arr) then
    std.flattenArrays([
      (if isStr(x) then [] else ['%s 每项必须是字符串' % label])
      for x in arr
    ])
  else [];

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
local jsonFlag(name, obj) = [name, std.manifestJsonMinified(obj)];

{
  apiVersion:: cliApiVersion,

  validate(paramsDoc)::
    local topErrors =
      if !isObj(paramsDoc) then
        ['params 必须是对象']
      else
        req(paramsDoc, 'apiVersion', function(v) isStr(v) && v == paramsApiVersion, 'params') +
        req(paramsDoc, 'scenario', isStr, 'params') +
        req(paramsDoc, 'serve', isObj, 'params') +
        req(paramsDoc, 'deployment', isObj, 'params') +
        req(paramsDoc, 'container', isObj, 'params') +
        req(paramsDoc, 'extras', isObj, 'params') +
        req(paramsDoc, 'warnings', isArr, 'params') +
        (if has(paramsDoc, 'warnings') && isArr(paramsDoc.warnings) then
           std.flattenArrays([
             (if isStr(w) then [] else ['params.warnings 每项必须是字符串'])
             for w in paramsDoc.warnings
           ])
         else []);

    local servePresent =
      isObj(paramsDoc) && has(paramsDoc, 'serve') && isObj(paramsDoc.serve);
    local serve = if servePresent then paramsDoc.serve else {};

    local serveErrors =
      if !servePresent then
        []
      else
        req(serve, 'model', isStr, 'serve') +
        req(serve, 'served_model_name', isStr, 'serve') +
        req(serve, 'tokenizer_mode', isStr, 'serve') +
        req(serve, 'host', isStr, 'serve') +
        req(serve, 'port', isPort, 'serve') +
        req(serve, 'tensor_parallel_size', function(v) isIntAtLeast(v, 1), 'serve') +
        req(serve, 'pipeline_parallel_size', function(v) isIntAtLeast(v, 1), 'serve') +
        req(serve, 'max_model_len', function(v) isIntAtLeast(v, 1), 'serve') +
        req(serve, 'max_num_batched_tokens', function(v) isIntAtLeast(v, 1), 'serve') +
        req(serve, 'max_cudagraph_capture_size', function(v) isIntAtLeast(v, 1), 'serve') +
        req(serve, 'gpu_memory_utilization', isGpuMem, 'serve') +
        req(serve, 'default_chat_template_kwargs', isObj, 'serve') +
        opt(serve, 'api_key', isStr, 'serve') +
        opt(serve, 'enable_expert_parallel', isBool, 'serve') +
        opt(serve, 'max_num_seqs', function(v) isIntAtLeast(v, 1), 'serve') +
        opt(serve, 'reasoning_parser', isStr, 'serve') +
        opt(serve, 'tool_call_parser', isStr, 'serve') +
        opt(serve, 'enable_auto_tool_choice', isBool, 'serve') +
        opt(serve, 'language_model_only', isBool, 'serve') +
        opt(serve, 'mm_encoder_tp_mode', isMmMode, 'serve') +
        opt(serve, 'disable_uvicorn_access_log', isBool, 'serve') +
        opt(serve, 'enforce_eager', isBool, 'serve') +
        (if !has(serve, 'speculative_config') then
           []
         else if !isObj(serve.speculative_config) then
           ['serve.speculative_config 必须是对象']
         else
           req(serve.speculative_config, 'method', isStr, 'serve.speculative_config') +
           req(serve.speculative_config, 'num_speculative_tokens', function(v) isIntAtLeast(v, 1), 'serve.speculative_config')) +
        (if (has(serve, 'language_model_only') && serve.language_model_only == true) == has(serve, 'mm_encoder_tp_mode') then
           ['serve 必须恰好设置 language_model_only: true 或 mm_encoder_tp_mode 之一']
         else []) +
        (if (has(serve, 'tool_call_parser') !=
             (has(serve, 'enable_auto_tool_choice') && serve.enable_auto_tool_choice == true)) then
           ['serve.tool_call_parser 与 enable_auto_tool_choice 必须成对出现']
         else []);

    local deploymentPresent =
      isObj(paramsDoc) && has(paramsDoc, 'deployment') && isObj(paramsDoc.deployment);
    local deployment = if deploymentPresent then paramsDoc.deployment else {};

    local nodes = if has(deployment, 'nodes') then deployment.nodes else null;
    local gpusPerNode = if has(deployment, 'gpus_per_node') then deployment.gpus_per_node else null;
    local backend = if has(deployment, 'distributed_executor_backend') then deployment.distributed_executor_backend else null;

    local deploymentErrors =
      if !deploymentPresent then
        []
      else
        req(deployment, 'nodes', function(v) isIntAtLeast(v, 1), 'deployment') +
        req(deployment, 'gpus_per_node', function(v) isIntAtLeast(v, 1), 'deployment') +
        req(deployment, 'node_ips', isArr, 'deployment') +
        (if has(deployment, 'node_ips') && isArr(deployment.node_ips) then
           std.flattenArrays([
             (if isStr(ip) && ip != '' then [] else ['deployment.node_ips 每项必须是非空字符串'])
             for ip in deployment.node_ips
           ])
         else []) +
        (if has(deployment, 'distributed_executor_backend') && !isBackend(backend) then
           ['deployment.distributed_executor_backend 必须是 local/ray/mp（当前：%s）' % show(backend)]
         else []) +
        (if isInt(nodes) && backend == 'local' && nodes != 1 then
           ['单机后端 local 只能用于 nodes=1']
         else []) +
        (if isInt(nodes) && nodes > 1 && backend == 'local' then
           ['多机时 distributed_executor_backend 不能是 local']
         else []) +
        (if isInt(nodes) && isArr(deployment.node_ips) && std.length(deployment.node_ips) != nodes then
           ['deployment.node_ips 数量必须等于 nodes：%d != %d' % [std.length(deployment.node_ips), nodes]]
         else []) +
        (if backend == 'ray' then
           req(deployment, 'ray_port', isPort, 'deployment') +
           (if has(deployment, 'master_port') then ['Ray 模式不应设置 deployment.master_port'] else [])
         else []) +
        (if backend == 'mp' then
           req(deployment, 'master_port', isPort, 'deployment') +
           (if has(deployment, 'ray_port') then ['mp 模式不应设置 deployment.ray_port'] else [])
         else []) +
        (if backend == 'local' then
           (if has(deployment, 'ray_port') || has(deployment, 'master_port') then
              ['单机模式不应设置 ray_port/master_port']
            else [])
         else []);

    local worldSizeErrors =
      if has(serve, 'tensor_parallel_size') && has(serve, 'pipeline_parallel_size') &&
         isInt(serve.tensor_parallel_size) && isInt(serve.pipeline_parallel_size) &&
         isInt(nodes) && isInt(gpusPerNode) &&
         serve.tensor_parallel_size * serve.pipeline_parallel_size != nodes * gpusPerNode then
        ['TP × PP 必须等于 nodes × gpus_per_node：%s × %s != %s × %s' % [
          show(serve.tensor_parallel_size),
          show(serve.pipeline_parallel_size),
          show(nodes),
          show(gpusPerNode),
        ]]
      else [];

    local containerPresent =
      isObj(paramsDoc) && has(paramsDoc, 'container') && isObj(paramsDoc.container);
    local container = if containerPresent then paramsDoc.container else {};

    local envErrors =
      if !has(container, 'environment') then
        ['container 缺少必填字段 environment']
      else if !isObj(container.environment) then
        ['container.environment 必须是对象']
      else
        std.flattenArrays([
          (if isStr(container.environment[k]) then [] else ['container.environment.%s 必须是字符串' % k])
          for k in std.objectFields(container.environment)
        ]);

    local mountErrors =
      if !has(container, 'mounts') then
        ['container 缺少必填字段 mounts']
      else if !isArr(container.mounts) then
        ['container.mounts 必须是数组']
      else
        std.flattenArrays([
          (if !isObj(m) then
             ['container.mounts 每项必须是对象']
           else
             req(m, 'host_path', isStr, 'container.mounts[]') +
             req(m, 'container_path', isStr, 'container.mounts[]') +
             req(m, 'read_only', isBool, 'container.mounts[]'))
          for m in container.mounts
        ]);

    local containerErrors =
      if !containerPresent then
        []
      else
        req(container, 'image', isStr, 'container') +
        envErrors +
        mountErrors +
        req(container, 'shm_size', isStr, 'container') +
        req(container, 'network_host', isBool, 'container') +
        req(container, 'name_prefix', isStr, 'container');

    local extrasPresent =
      isObj(paramsDoc) && has(paramsDoc, 'extras') && isObj(paramsDoc.extras);
    local extras = if extrasPresent then paramsDoc.extras else {};

    local extrasErrors =
      if !extrasPresent then
        []
      else
        req(extras, 'serve_args', isArr, 'extras') +
        req(extras, 'docker_args', isArr, 'extras') +
        stringArrayErrors(extras.serve_args, 'extras.serve_args') +
        stringArrayErrors(extras.docker_args, 'extras.docker_args');

    {
      errors:
        topErrors +
        serveErrors +
        deploymentErrors +
        worldSizeErrors +
        containerErrors +
        extrasErrors,
    },

  render(paramsDoc)::
    local v = $.validate(paramsDoc);

    local s = paramsDoc.serve;
    local d = paramsDoc.deployment;
    local c = paramsDoc.container;
    local x = paramsDoc.extras;

    local distributedPairs(rank) =
      if d.nodes <= 1 then
        []
      else if d.distributed_executor_backend == 'ray' then
        [flag('--distributed-executor-backend', 'ray')]
      else
        [
          flag('--distributed-executor-backend', 'mp'),
          flag('--nnodes', d.nodes),
          flag('--node-rank', rank),
          flag('--master-addr', d.node_ips[0]),
          flag('--master-port', d.master_port),
        ]
        + (if rank > 0 then [flagOnly('--headless')] else []);

    local prePairs =
      [
        flag('--served-model-name', s.served_model_name),
        flag('--host', s.host),
        flag('--port', s.port),
      ]
      + (if has(s, 'api_key') then [flag('--api-key', s.api_key)] else [])
      + [
        flag('--tokenizer-mode', s.tokenizer_mode),
        flag('--tensor-parallel-size', s.tensor_parallel_size),
      ]
      + (if s.pipeline_parallel_size > 1 then
           [flag('--pipeline-parallel-size', s.pipeline_parallel_size)]
         else [])
      + (if has(s, 'enable_expert_parallel') && s.enable_expert_parallel == true then
           [flagOnly('--enable-expert-parallel')]
         else []);

    local postPairs =
      [
        flag('--max-model-len', s.max_model_len),
        flag('--max-num-batched-tokens', s.max_num_batched_tokens),
        flag('--max-cudagraph-capture-size', s.max_cudagraph_capture_size),
        flag('--gpu-memory-utilization', s.gpu_memory_utilization),
      ]
      + (if has(s, 'max_num_seqs') then [flag('--max-num-seqs', s.max_num_seqs)] else [])
      + (if has(s, 'speculative_config') then
           [jsonFlag('--speculative-config', s.speculative_config)]
         else [])
      + (if has(s, 'reasoning_parser') then
           [flag('--reasoning-parser', s.reasoning_parser)]
         else [])
      + [jsonFlag('--default-chat-template-kwargs', s.default_chat_template_kwargs)]
      + (if has(s, 'tool_call_parser') then
           [flag('--tool-call-parser', s.tool_call_parser)]
         else [])
      + (if has(s, 'enable_auto_tool_choice') && s.enable_auto_tool_choice == true then
           [flagOnly('--enable-auto-tool-choice')]
         else [])
      + (if has(s, 'mm_encoder_tp_mode') then
           [flag('--mm-encoder-tp-mode', s.mm_encoder_tp_mode)]
         else if has(s, 'language_model_only') && s.language_model_only == true then
           [flagOnly('--language-model-only')]
         else [])
      + (if has(s, 'disable_uvicorn_access_log') && s.disable_uvicorn_access_log == true then
           [flagOnly('--disable-uvicorn-access-log')]
         else [])
      + (if has(s, 'enforce_eager') && s.enforce_eager == true then
           [flagOnly('--enforce-eager')]
         else []);

    local extraServePairs =
      if isArr(x.serve_args) then [[a] for a in x.serve_args] else [];

    local serveArgv(rank) =
      ['vllm', 'serve', s.model]
      + std.flattenArrays(prePairs + distributedPairs(rank) + postPairs + extraServePairs);

    local dockerFor(rank, isHead, nodeEnv, inner) =
      local envPairs = [
        { key: k, value: str(nodeEnv[k]) }
        for k in std.objectFields(nodeEnv)
        if nodeEnv[k] != null
      ];
      local envArgs = std.flattenArrays([['-e', e.key + '=' + e.value] for e in envPairs]);
      local mountArgs = std.flattenArrays([
        ['-v', m.host_path + ':' + m.container_path + (if m.read_only then ':ro' else '')]
        for m in c.mounts
      ]);
      local portArgs =
        if c.network_host then
          []
        else if isHead then
          if d.nodes <= 1 then
            ['-p', str(s.port) + ':' + str(s.port)]
          else if d.distributed_executor_backend == 'ray' then
            ['-p', str(s.port) + ':' + str(s.port), '-p', str(d.ray_port) + ':' + str(d.ray_port)]
          else
            ['-p', str(s.port) + ':' + str(s.port), '-p', str(d.master_port) + ':' + str(d.master_port)]
        else
          [];
      local dockerArgv =
        [
          'docker',
          'run',
          '--name',
          c.name_prefix + '-node-' + str(rank),
          '--gpus',
          'all',
          '--ipc',
          'host',
          '--shm-size',
          c.shm_size,
        ]
        + (if c.network_host then ['--network', 'host'] else portArgs)
        + envArgs
        + mountArgs
        + (if isArr(x.docker_args) then x.docker_args else [])
        + ['--entrypoint', 'bash', c.image, '-c', inner];
      {
        argv: dockerArgv,
        command: joinArgs(dockerArgv),
      };

    local mkNode(rank) =
      local ip = d.node_ips[rank];
      local isHead = rank == 0;
      local role =
        if d.nodes <= 1 then 'server'
        else if isHead then 'head'
        else 'worker';

      local nodeEnv =
        c.environment + (if d.nodes > 1 then { VLLM_HOST_IP: ip } else {});

      local serveNodeArgv = serveArgv(rank);

      local rayHeadArgv = [
        'ray',
        'start',
        '--head',
        '--port=' + str(d.ray_port),
        '--node-ip-address=' + ip,
        '--num-gpus=' + str(d.gpus_per_node),
        '--disable-usage-stats',
      ];
      local rayWorkerArgv = [
        'ray',
        'start',
        '--address=' + d.node_ips[0] + ':' + str(d.ray_port),
        '--node-ip-address=' + ip,
        '--num-gpus=' + str(d.gpus_per_node),
        '--block',
        '--disable-usage-stats',
      ];

      local inner =
        if d.nodes <= 1 then
          joinArgs(serveNodeArgv)
        else if d.distributed_executor_backend == 'mp' then
          joinArgs(serveNodeArgv)
        else if isHead then
          joinArgs(rayHeadArgv) + ' && ' + joinArgs(serveNodeArgv)
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
          if d.distributed_executor_backend == 'ray' && !isHead then
            null
          else {
            argv: serveNodeArgv,
            command: joinArgs(serveNodeArgv),
          },
        ray:
          if d.nodes > 1 && d.distributed_executor_backend == 'ray' then {
            argv: if isHead then rayHeadArgv else rayWorkerArgv,
            command: joinArgs(if isHead then rayHeadArgv else rayWorkerArgv),
          } else null,
        docker: docker,
        command: docker.command,
      };

    local nodeObjects = [mkNode(i) for i in std.range(0, d.nodes - 1)];

    local mode =
      if d.nodes <= 1 then 'single-node'
      else if d.distributed_executor_backend == 'ray' then 'ray-multi-node'
      else 'mp-multi-node';

    {
      assert std.length(v.errors) == 0 : std.join('; ', v.errors),

      apiVersion: cliApiVersion,
      meta: {
        sourceApiVersion: paramsDoc.apiVersion,
        scenario: paramsDoc.scenario,
      },
      cli: {
        serve: {
          model: s.model,
          servedModelName: s.served_model_name,
          argv: serveArgv(0),
          command: joinArgs(serveArgv(0)),
        },
        deployment: {
          mode: mode,
          nodes: nodeObjects,
          commands: [n.command for n in nodeObjects],
        },
      },
      warnings: paramsDoc.warnings,
    },
}
