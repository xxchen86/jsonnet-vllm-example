// DeepSeek-V4.1-Flash 模型事实、能力、运行时与 recipe 默认。
// 这是普通 Jsonnet 数据，由静态模板选择性使用。

{
  id: 'deepseek-ai/DeepSeek-V4.1-Flash',
  servedModelName: 'deepseek-ai/DeepSeek-V4.1-Flash',
  layers: 40,
  weightsGiB: 511,
  vramFloorGiB: 614,
  image: 'vllm/vllm-openai:deepseekv41-flash-0909',

  capabilities: {
    tokenizerMode: 'deepseek_v41',
    reasoningParser: 'deepseek_v41',
    toolParser: 'deepseek_v41',
    supportsMultimodal: true,
  },

  reasoningEffortAliases: {
    low: 25,
    high: 50,
    xhigh: 75,
    max: 100,
  },

  runtime: {
    containerNamePrefix: 'dsv41',
    environment: {
      VLLM_USE_RUST_FRONTEND: '1',
    },
  },

  recipe: {
    maxModelLen: 1048576,
    maxNumBatchedTokens: 16384,
    maxCudagraphCaptureSize: 1024,
    gpuMemoryUtilization: 0.9,
  },

  features: {
    speculative: true,
    speculativeDefaults: {
      enabled: true,
      method: 'dspark',
      numSpeculativeTokens: 5,
      draftSampleMethod: 'probabilistic',
      rejectionSampleMethod: 'block',
      enableAdaptiveVerification: false,
    },
    thinking: true,
    reasoningEffort: 50,
    toolCalling: true,
    multimodal: false,
    mmEncoderTpMode: 'data',
    expertParallel: true,
  },
}
