// 阶段 2 断言测试：jsonnet vllm/cli-tests.jsonnet
// 断言失败时 jsonnet 以非 0 退出。

local cli = import 'lib/cli.libsonnet';
local params = import 'lib/params.libsonnet';

local has(obj, key) = std.type(obj) == 'object' && std.objectHas(obj, key);
local hasArg(argv, name) = std.length(std.find(name, argv)) > 0;

local argValue(argv, name) =
  local idx = std.find(name, argv);
  if std.length(idx) == 0 then
    error 'missing arg: ' + name
  else
    argv[idx[0] + 1];

local idxOf(arr, value) =
  local idx = std.find(value, arr);
  if std.length(idx) == 0 then -1 else idx[0];

local hasErr(errors, needle) =
  std.length(std.findSubstr(needle, std.join('; ', errors))) > 0;

local base = { nodes: 1, gpusPerNode: 8, gpuMemoryGiB: 141 };

local singleParams = params.generate(base);
local single = cli.render(singleParams);
local gb200 = cli.render(params.generate({ nodes: 1, gpusPerNode: 4, gpuMemoryGiB: 192 }));
local multiPpParams = params.generate(base { nodes: 2, parallelMode: 'tp-pp' });
local multiPp = cli.render(multiPpParams);
local multiTp = cli.render(params.generate(base { nodes: 2, parallelMode: 'tp' }));
local multiMp = cli.render(params.generate(base { nodes: 2, parallelMode: 'tp', distributedBackend: 'mp' }));
local noSpec = cli.render(params.generate(base { speculative: false }));
local noThink = cli.render(params.generate(base { thinking: false }));
local noTool = cli.render(params.generate(base { toolCalling: false }));
local mm = cli.render(params.generate(base { multimodal: true }));
local effortAlias = cli.render(params.generate(base { reasoningEffort: 'max' }));
local effortNone = cli.render(params.generate(base { reasoningEffort: 'none' }));
local extras = cli.render(params.generate(base {
  extraArgs: ['--enable-prefix-caching'],
  extraDockerArgs: ['--ulimit', 'nofile=65535:65535'],
}));
local noHostNetwork = cli.render(params.generate(base { dockerNetworkHost: false }));
local multiPpNoHost = cli.render(params.generate(base {
  nodes: 2,
  parallelMode: 'tp-pp',
  dockerNetworkHost: false,
}));
local multiMpNoHost = cli.render(params.generate(base {
  nodes: 2,
  parallelMode: 'tp',
  distributedBackend: 'mp',
  dockerNetworkHost: false,
}));
local options = cli.render(params.generate(base {
  apiKey: 'test-key',
  maxNumSeqs: 128,
  enforceEager: true,
  disableUvicornAccessLog: false,
}));
local endpoint = cli.render(params.generate(base { host: '127.0.0.1', port: 9000 }));
local withMounts = cli.render(params.generate(base {
  modelHostPath: '/host/models/DeepSeek-V4.1-Flash',
  modelPath: '/models/DeepSeek-V4.1-Flash',
}));

local threeNodesParams = params.generate(base { nodes: 3 });
local threeNodes = cli.render(threeNodesParams);

local specConfig = std.parseJson(argValue(single.cli.serve.argv, '--speculative-config'));
local noThinkKwargs = std.parseJson(argValue(noThink.cli.serve.argv, '--default-chat-template-kwargs'));
local effortAliasKwargs = std.parseJson(argValue(effortAlias.cli.serve.argv, '--default-chat-template-kwargs'));
local effortNoneKwargs = std.parseJson(argValue(effortNone.cli.serve.argv, '--default-chat-template-kwargs'));

local badVersion = singleParams { apiVersion: 'vllm-params/v2' };
local badModel = singleParams { serve: singleParams.serve { model: null } };
local badWorld = singleParams { serve: singleParams.serve { tensor_parallel_size: 4 } };
local badIps = singleParams {
  deployment: singleParams.deployment { nodes: 2, node_ips: ['10.0.0.10'] },
};
local badRayPort = singleParams {
  serve: singleParams.serve {
    tensor_parallel_size: 8,
    pipeline_parallel_size: 2,
  },
  deployment: singleParams.deployment {
    nodes: 2,
    node_ips: ['10.0.0.10', '10.0.0.11'],
    distributed_executor_backend: 'ray',
    ray_port: 6379,
    master_port: 29501,
  },
};
local badSpec = singleParams { serve: singleParams.serve { speculative_config: 'dspark' } };
local badMm = singleParams { serve: singleParams.serve { mm_encoder_tp_mode: 'data' } };
local badExtras = singleParams { extras: singleParams.extras { serve_args: ['ok', 1] } };

{
  // CLI 产物形状：独立 cli 分区，不含参数生成侧字段
  assert single.apiVersion == 'vllm-cli/v1' : 'cli apiVersion',
  assert std.objectFields(single) == ['apiVersion', 'cli', 'meta', 'warnings'] : 'cli top-level keys',
  assert !has(single, 'parallel') : 'no parallel',
  assert !has(single, 'features') : 'no features',
  assert !has(single, 'serve') : 'no top-level serve',
  assert !has(single, 'deployment') : 'no top-level deployment',
  assert single.meta.sourceApiVersion == 'vllm-params/v1' : 'meta source apiVersion',
  assert single.meta.scenario == singleParams.scenario : 'meta scenario',
  assert has(single, 'cli') && has(single.cli, 'serve') && has(single.cli, 'deployment') : 'cli partitions',

  // 单机 8 卡：argv 顺序 / 旗标
  assert single.cli.serve.model == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'single serve model',
  assert single.cli.serve.servedModelName == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'single served model name',
  assert argValue(single.cli.serve.argv, '--served-model-name') == 'deepseek-ai/DeepSeek-V4.1-Flash' : 'served name flag',
  assert argValue(single.cli.serve.argv, '--host') == '0.0.0.0' : 'host flag',
  assert argValue(single.cli.serve.argv, '--port') == '8000' : 'port flag',
  assert argValue(single.cli.serve.argv, '--tokenizer-mode') == 'deepseek_v41' : 'tokenizer mode flag',
  assert argValue(single.cli.serve.argv, '--tensor-parallel-size') == '8' : 'TP flag',
  assert !hasArg(single.cli.serve.argv, '--pipeline-parallel-size') : 'PP1 omitted',
  assert hasArg(single.cli.serve.argv, '--enable-expert-parallel') : 'EP flag',
  assert argValue(single.cli.serve.argv, '--max-model-len') == '1048576' : 'max model len flag',
  assert argValue(single.cli.serve.argv, '--max-num-batched-tokens') == '16384' : 'max batched tokens flag',
  assert argValue(single.cli.serve.argv, '--max-cudagraph-capture-size') == '1024' : 'cudagraph flag',
  assert argValue(single.cli.serve.argv, '--gpu-memory-utilization') == '0.9' : 'gpu mem util flag',
  assert hasArg(single.cli.serve.argv, '--language-model-only') : 'language model only flag',
  assert !hasArg(single.cli.serve.argv, '--mm-encoder-tp-mode') : 'no mm mode flag',
  assert hasArg(single.cli.serve.argv, '--disable-uvicorn-access-log') : 'disable access log flag',
  assert !hasArg(single.cli.serve.argv, '--api-key') : 'no api key',
  assert !hasArg(single.cli.serve.argv, '--max-num-seqs') : 'no max num seqs',
  assert !hasArg(single.cli.serve.argv, '--enforce-eager') : 'no enforce eager',

  // 投机 / thinking / tool calling 解析
  assert specConfig.method == 'dspark' : 'spec method',
  assert specConfig.num_speculative_tokens == 5 : 'spec tokens',
  assert argValue(single.cli.serve.argv, '--reasoning-parser') == 'deepseek_v41' : 'reasoning parser flag',
  assert argValue(single.cli.serve.argv, '--tool-call-parser') == 'deepseek_v41' : 'tool parser flag',
  assert hasArg(single.cli.serve.argv, '--enable-auto-tool-choice') : 'auto tool choice flag',
  assert std.parseJson(argValue(single.cli.serve.argv, '--default-chat-template-kwargs')).thinking == true : 'thinking kwargs',
  assert !hasArg(noSpec.cli.serve.argv, '--speculative-config') : 'spec off removes flag',
  assert !hasArg(noThink.cli.serve.argv, '--reasoning-parser') : 'thinking off removes parser',
  assert noThinkKwargs.thinking == false : 'thinking off kwargs',
  assert noThinkKwargs.reasoning_effort == 'none' : 'thinking off effort',
  assert !hasArg(noTool.cli.serve.argv, '--tool-call-parser') : 'tool off removes parser',
  assert !hasArg(noTool.cli.serve.argv, '--enable-auto-tool-choice') : 'tool off removes auto choice',
  assert !hasArg(mm.cli.serve.argv, '--language-model-only') : 'multimodal removes language-model-only',
  assert argValue(mm.cli.serve.argv, '--mm-encoder-tp-mode') == 'data' : 'multimodal mm mode',
  assert effortAliasKwargs.reasoning_effort == 100 : 'max alias in kwargs',
  assert !hasArg(effortNone.cli.serve.argv, '--reasoning-parser') : 'effort none removes parser',
  assert effortNoneKwargs.thinking == false : 'effort none kwargs',
  assert effortNoneKwargs.reasoning_effort == 'none' : 'effort none effort',

  // 单机部署 / Docker
  assert single.cli.deployment.mode == 'single-node' : 'single mode',
  assert std.length(single.cli.deployment.nodes) == 1 : 'single node count',
  assert single.cli.deployment.nodes[0].role == 'server' : 'single role',
  assert hasArg(single.cli.deployment.nodes[0].docker.argv, '--network') : 'single network host',
  assert hasArg(single.cli.deployment.nodes[0].docker.argv, '--gpus') : 'single gpus',
  assert hasArg(single.cli.deployment.nodes[0].docker.argv, '--shm-size') : 'single shm size',
  assert !hasArg(single.cli.deployment.nodes[0].docker.argv, '-v') : 'single no mount',
  assert hasArg(single.cli.deployment.nodes[0].docker.argv, '-e') : 'single env',
  assert !hasArg(single.cli.deployment.nodes[0].docker.argv, '-p') : 'single no ports with network host',
  assert hasArg(withMounts.cli.deployment.nodes[0].docker.argv, '-v') : 'withMounts mount flag',
  assert hasArg(withMounts.cli.deployment.nodes[0].docker.argv, '/host/models/DeepSeek-V4.1-Flash:/models/DeepSeek-V4.1-Flash:ro') : 'withMounts mount value',

  // Ray 多机
  assert multiPp.cli.deployment.mode == 'ray-multi-node' : 'ray mode',
  assert multiPp.cli.deployment.nodes[0].role == 'head' : 'ray head role',
  assert multiPp.cli.deployment.nodes[1].role == 'worker' : 'ray worker role',
  assert hasArg(multiPp.cli.deployment.nodes[0].ray.argv, '--head') : 'ray head arg',
  assert hasArg(multiPp.cli.deployment.nodes[1].ray.argv, '--address=10.0.0.10:6379') : 'ray worker address',
  assert argValue(multiPp.cli.deployment.nodes[0].serve.argv, '--distributed-executor-backend') == 'ray' : 'ray serve backend',
  assert !hasArg(multiPp.cli.serve.argv, '--nnodes') : 'ray mode must not pass nnodes',
  assert multiPp.cli.deployment.nodes[1].serve == null : 'ray worker serve null',
  assert argValue(multiPp.cli.deployment.nodes[0].serve.argv, '--pipeline-parallel-size') == '2' : 'ray PP2 flag',
  assert std.length(multiPp.cli.deployment.commands) == 2 : 'ray commands count',

  // 跨机 TP
  assert argValue(multiTp.cli.serve.argv, '--tensor-parallel-size') == '16' : 'multiTp TP16',
  assert !hasArg(multiTp.cli.serve.argv, '--pipeline-parallel-size') : 'multiTp PP1 omitted',

  // mp 多机
  assert multiMp.cli.deployment.mode == 'mp-multi-node' : 'mp mode',
  assert argValue(multiMp.cli.deployment.nodes[0].serve.argv, '--node-rank') == '0' : 'mp head rank 0',
  assert argValue(multiMp.cli.deployment.nodes[1].serve.argv, '--node-rank') == '1' : 'mp worker rank 1',
  assert hasArg(multiMp.cli.deployment.nodes[1].serve.argv, '--headless') : 'mp worker headless',
  assert !hasArg(multiMp.cli.deployment.nodes[0].serve.argv, '--headless') : 'mp head not headless',
  assert multiMp.cli.deployment.nodes[1].ray == null : 'mp mode has no ray command',
  assert argValue(multiMp.cli.serve.argv, '--nnodes') == '2' : 'mp nnodes',
  assert argValue(multiMp.cli.serve.argv, '--master-addr') == '10.0.0.10' : 'mp master addr',
  assert argValue(multiMp.cli.serve.argv, '--master-port') == '29501' : 'mp master port',
  assert hasArg(multiMp.cli.deployment.nodes[0].docker.argv, '--network') : 'mp network host',

  // 端口映射（network_host=false）
  assert argValue(noHostNetwork.cli.deployment.nodes[0].docker.argv, '-p') == '8000:8000' : 'single port mapping',
  assert !hasArg(noHostNetwork.cli.deployment.nodes[0].docker.argv, '--network') : 'single no network host',
  assert hasArg(multiPpNoHost.cli.deployment.nodes[0].docker.argv, '6379:6379') : 'ray port mapping',
  assert !hasArg(multiPpNoHost.cli.deployment.nodes[1].docker.argv, '-p') : 'ray worker no port',
  assert hasArg(multiMpNoHost.cli.deployment.nodes[0].docker.argv, '29501:29501') : 'mp port mapping',

  // 逃生舱
  assert hasArg(extras.cli.serve.argv, '--enable-prefix-caching') : 'extra serve arg',
  assert hasArg(extras.cli.deployment.nodes[0].docker.argv, '--ulimit') : 'extra docker arg',
  assert idxOf(extras.cli.deployment.nodes[0].docker.argv, '--ulimit') <
         idxOf(extras.cli.deployment.nodes[0].docker.argv, '--entrypoint') : 'extra docker arg position',
  assert !hasArg(single.cli.deployment.nodes[0].docker.argv, '--ulimit') : 'no extra docker arg by default',

  // 可选 vLLM 参数
  assert argValue(options.cli.serve.argv, '--api-key') == 'test-key' : 'api key flag',
  assert argValue(options.cli.serve.argv, '--max-num-seqs') == '128' : 'max num seqs flag',
  assert hasArg(options.cli.serve.argv, '--enforce-eager') : 'enforce eager flag',
  assert !hasArg(options.cli.serve.argv, '--disable-uvicorn-access-log') : 'disable access log off',
  assert argValue(endpoint.cli.serve.argv, '--host') == '127.0.0.1' : 'host override',
  assert argValue(endpoint.cli.serve.argv, '--port') == '9000' : 'port override',

  // warnings 透传
  assert std.length(threeNodes.warnings) > 0 : 'warning passthrough non-empty',
  assert threeNodes.warnings == threeNodesParams.warnings : 'warning passthrough exact',

  // schema 负例
  assert hasErr(cli.validate(badVersion).errors, 'apiVersion') : 'bad version error',
  assert hasErr(cli.validate(badModel).errors, 'serve.model') : 'bad model error',
  assert hasErr(cli.validate(badWorld).errors, 'TP × PP') : 'bad world size error',
  assert hasErr(cli.validate(badIps).errors, 'node_ips 数量必须等于 nodes') : 'bad node ips error',
  assert hasErr(cli.validate(badRayPort).errors, 'master_port') : 'bad ray port error',
  assert hasErr(cli.validate(badSpec).errors, 'speculative_config') : 'bad spec config error',
  assert hasErr(cli.validate(badMm).errors, 'language_model_only') : 'bad multimodal error',
  assert hasErr(cli.validate(badExtras).errors, 'serve_args') : 'bad extras error',

  summary: {
    cases: 19,
    negatives: 8,
    singleTP: singleParams.serve.tensor_parallel_size,
    multiRayMode: multiPp.cli.deployment.mode,
    multiMpMode: multiMp.cli.deployment.mode,
    warnings: threeNodes.warnings,
  },
}
