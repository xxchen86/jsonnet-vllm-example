// 默认高层静态模板：DeepSeek-V4.1-Flash on 8×H200。
//
// 这是普通 Jsonnet 函数，返回 vllm-params/v1 静态模板结果。
// 模板开发者可以调用辅助函数，也可以把任意字段换成本地字面量。

function(config={})
  local h = import '../lib/launch-helpers.libsonnet';
  local model = import 'profiles/models/deepseek-v41-flash.libsonnet';
  local hardware = import 'profiles/hardware/h200.libsonnet';

  local launch = {
    host: '0.0.0.0',
    port: 8000,
    environment: {
      VLLM_ENGINE_READY_TIMEOUT_S: '3600',
    },
    parallelMode: 'auto',
    distributedBackend: 'ray',
    nodeIpPattern: '10.0.0.%d',
    nodeIpStart: 10,
    rayPort: 6379,
    masterPort: 29501,
  };

  local ctx = h.context({
    model: model,
    hardware: hardware,
    launch: launch,
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
  })
