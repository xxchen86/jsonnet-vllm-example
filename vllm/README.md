# DeepSeek-V4.1-Flash × vLLM 启动参数模板（Jsonnet，两阶段）

把 [vLLM 官方 recipe](https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash) 的 `vllm serve` 参数收敛成两阶段 Jsonnet 模板：

- **阶段 1：参数生成** —— 场景配置（机器数、卡数、功能开关）→ `vllm` 原生参数产物（`vllm-params/v1`）；
- **阶段 2：CLI 渲染** —— 参数产物 → `argv`、shell 命令、Docker / Ray / mp 逐机命令（`vllm-cli/v1`）。

参数产物刻意使用 **vLLM 原生参数名**（snake_case，对应 `EngineArgs` / `vllm serve`），并按 `serve` / `deployment` / `container` 分区，方便有 vLLM 经验的开发者直接阅读和比对。

> 目标镜像：`vllm/vllm-openai:deepseekv41-flash-0909`（要求 vLLM >= 0.31.0）。
> 模型权重约 511 GB（含 196B Engram 记忆表），官方建议至少 614 GB 显存（511 GB × 1.2）。

## 目录

```text
vllm/
├── generate-params.jsonnet      # 阶段 1 入口：场景配置 -> 参数产物
├── render-cli.jsonnet           # 阶段 2 入口：参数产物 -> CLI 产物
├── lib/
│   ├── params.libsonnet         # 参数生成：默认值 / 校验 / TP-PP / 功能映射
│   ├── cli.libsonnet            # CLI 渲染：schema 校验 / argv / shell / Docker / Ray / mp
│   └── parallel.libsonnet       # TP/PP 推导、校验、每机 IP
├── params/                      # 场景输入
│   ├── single-h200-8gpu.json
│   ├── single-h200-8gpu-switches-off.json
│   ├── single-gb200-4gpu.json
│   ├── multi-h200-2x8-ray.json
│   └── multi-h200-2x8-mp-tp16.json
├── params-tests.jsonnet         # 阶段 1 断言（含 validate 负例）
├── cli-tests.jsonnet            # 阶段 2 断言（含 validate 负例）
├── golden-tests.jsonnet         # 新旧 CLI 投影等价性测试
├── tests/golden/legacy-render.json  # 改造前冻结的 5 场景基线
├── render-params.sh             # 阶段 1 文件落盘脚本
├── render-cli.sh                # 阶段 2 文件落盘脚本
└── run-tests.sh                 # 三层测试 + 所有场景的两阶段渲染
```

## 快速开始

### Linux / WSL

```bash
mkdir -p vllm/out

# 阶段 1：生成参数产物
jsonnet vllm/generate-params.jsonnet \
  --tla-code-file config=vllm/params/single-h200-8gpu.json \
  > vllm/out/single-h200-8gpu.params.json

# 阶段 2：渲染 CLI
jsonnet vllm/render-cli.jsonnet \
  --tla-code-file params=vllm/out/single-h200-8gpu.params.json \
  > vllm/out/single-h200-8gpu.cli.json
```

### Shell 脚本

```bash
./vllm/render-params.sh \
  -c vllm/params/single-h200-8gpu.json \
  -o vllm/out/single-h200-8gpu.params.json

./vllm/render-cli.sh \
  -p vllm/out/single-h200-8gpu.params.json \
  -o vllm/out/single-h200-8gpu.cli.json
```

脚本会 `cd` 到仓库根目录，`-c` / `-p` / `-o` 的路径都按仓库根目录解析；省略 `-o` 时输出到 stdout。

也可以内联覆盖场景参数：

```bash
jsonnet vllm/generate-params.jsonnet --tla-code config='{nodes: 2, gpusPerNode: 8, speculative: true}'
```

## 输入参数

### 核心字段

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `nodes` | `1` | 机器数量 |
| `totalGpus` | `null` | 可选：总卡数；设置后按 `nodes` 推导每机卡数，必须能被 `nodes` 整除 |
| `gpusPerNode` | `8` | 每台机器的 GPU 数；与 `totalGpus` 同时设置且冲突时报错 |
| `gpuMemoryGiB` | `141` | 单卡显存（H200=141，H100=80，B200/GB200=192），仅用于显存下限提示 |
| `modelLayers` | `40` | 模型层数，仅用于 PP 整除性提示 |
| `parallelMode` | `"auto"` | `auto` / `tp` / `tp-pp` |
| `tensorParallel` | `null` | 显式指定 TP，覆盖推导值 |
| `pipelineParallel` | `null` | 显式指定 PP，覆盖推导值 |
| `expertParallel` | `true` | TP > 1 时启用 expert parallel |
| `distributedBackend` | `"ray"` | 多机后端：`ray` 或 `mp`；单机忽略 |
| `nodeIpPattern` | `"10.0.0.%d"` | 按机器序号格式化 IP |
| `nodeIpStart` | `10` | IP 起始值 |
| `nodeIps` | `[]` | 显式 IP 列表；非空时优先于 `nodeIpPattern` |
| `rayPort` | `6379` | Ray head 端口 |
| `masterPort` | `29501` | mp 后端 rendezvous 端口 |

### 功能开关

| 字段 | 默认值 | 映射到参数产物 |
| --- | --- | --- |
| `speculative` | `true` | `serve.speculative_config` |
| `thinking` | `true` | `serve.reasoning_parser` + `serve.default_chat_template_kwargs` |
| `reasoningEffort` | `50` | 写入 `serve.default_chat_template_kwargs.reasoning_effort`；支持 1-100、`low`/`high`/`xhigh`/`max`/`none` |
| `toolCalling` | `true` | `serve.tool_call_parser` + `serve.enable_auto_tool_choice` |
| `multimodal` | `false` | false → `serve.language_model_only`；true → `serve.mm_encoder_tp_mode` |
| `mmEncoderTpMode` | `"data"` | 多模态编码器并行模式：`data` 或 `weights` |

`speculative` 用对象写法可以覆盖 DSpark 细节：

```json
{
  "speculative": {
    "enabled": true,
    "method": "dspark",
    "numSpeculativeTokens": 5,
    "draftSampleMethod": "probabilistic",
    "rejectionSampleMethod": "block",
    "enableAdaptiveVerification": true
  }
}
```

### 模型、服务与容器

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `model` | `"deepseek-ai/DeepSeek-V4.1-Flash"` | HuggingFace model id |
| `modelPath` | `null` | 容器内模型路径；设置后作为 `vllm serve` 的 model 位置参数 |
| `modelHostPath` | `null` | 宿主机模型目录；与 `modelPath` 同时设置时自动挂载 |
| `image` | `"vllm/vllm-openai:deepseekv41-flash-0909"` | vLLM 镜像 |
| `host` / `port` | `"0.0.0.0"` / `8000` | HTTP 监听地址 |
| `apiKey` | `null` | 设置后写入参数产物 `serve.api_key` |
| `maxModelLen` | `1048576` | 官方 recipe 的 1M 上下文 |
| `maxNumBatchedTokens` | `16384` | 官方 recipe 默认 |
| `maxCudagraphCaptureSize` | `1024` | 官方 recipe 默认 |
| `gpuMemoryUtilization` | `0.9` | 官方 recipe 默认 |
| `maxNumSeqs` | `null` | 不设置则省略 |
| `enforceEager` | `false` | 设为 `true` 时生成 `serve.enforce_eager` |
| `disableUvicornAccessLog` | `true` | 设为 `true` 时生成 `serve.disable_uvicorn_access_log` |
| `dockerShmSize` | `"32g"` | Docker `--shm-size` |
| `dockerNetworkHost` | `true` | 多机建议保持 `true`（`--network host`） |
| `hfHubOffline` | `false` | 设为 `true` 时追加 `HF_HUB_OFFLINE=1` |

### 逃生舱

| 字段 | 产物落点 | 说明 |
| --- | --- | --- |
| `extraEnv` | `container.environment` | 追加/覆盖容器环境变量；值统一转成字符串 |
| `extraMounts` | `container.mounts` | 追加挂载，元素形如 `{hostPath, containerPath, readOnly}` |
| `extraDockerArgs` | `extras.docker_args` | 原样追加到 `docker run`（阶段 2 不解释） |
| `extraArgs` | `extras.serve_args` | 原样追加到 `vllm serve` 末尾（阶段 2 不解释） |

## 并行推导

设 `N = nodes`、`G = gpusPerNode`、总卡数 `W = N × G`。

| `parallelMode` | 单机（N=1） | 多机（N>1） |
| --- | --- | --- |
| `auto` | `TP=G`, `PP=1` | `TP=G`, `PP=N` |
| `tp` | `TP=G`, `PP=1` | `TP=N×G`, `PP=1` |
| `tp-pp` | `TP=G`, `PP=1` | `TP=G`, `PP=N` |

约束与提示：

- 必须满足 `TP × PP == W`，否则阶段 1 直接报错；
- 卡数可以传 `totalGpus` 或 `gpusPerNode`；`totalGpus` 必须能被 `nodes` 整除；
- 显式传入 `tensorParallel` / `pipelineParallel` 时优先使用显式值，但仍要满足上面的等式；
- 模型共 40 层，PP 建议取 40 的约数（1/2/4/5/8/10/20/40）。例如 3 机 `auto` 会得到 `PP=3`，模板会给出警告，建议改用 `parallelMode: "tp"`；
- 总显存低于 614 GB 时会给出警告，但不会阻止渲染。

常见组合：

| 场景 | 配置 | 参数产物 |
| --- | --- | --- |
| 单机 8 卡 | `nodes=1, gpusPerNode=8` | `serve.tensor_parallel_size=8`, `pipeline_parallel_size=1` |
| 单机 4 卡 | `nodes=1, gpusPerNode=4` | `tensor_parallel_size=4`, `pipeline_parallel_size=1` |
| 2 机 × 8 卡，机内 TP | `nodes=2, parallelMode="tp-pp"` | `tensor_parallel_size=8`, `pipeline_parallel_size=2` |
| 2 机 × 8 卡，跨机 TP | `nodes=2, parallelMode="tp"` | `tensor_parallel_size=16`, `pipeline_parallel_size=1` |
| 4 机 × 4 卡，跨机 TP | `nodes=4, gpusPerNode=4, parallelMode="tp"` | `tensor_parallel_size=16`, `pipeline_parallel_size=1` |

## 阶段 1 产物：`vllm-params/v1`

单机 8×H200 场景的产物（节选）：

```jsonc
{
  "apiVersion": "vllm-params/v1",
  "scenario": "单机 8×H200：TP8，开启 DSpark 投机、thinking、tool calling",
  "serve": {
    "model": "/models/DeepSeek-V4.1-Flash",
    "served_model_name": "deepseek-ai/DeepSeek-V4.1-Flash",
    "tokenizer_mode": "deepseek_v41",
    "host": "0.0.0.0",
    "port": 8000,
    "tensor_parallel_size": 8,
    "pipeline_parallel_size": 1,
    "enable_expert_parallel": true,
    "max_model_len": 1048576,
    "max_num_batched_tokens": 16384,
    "max_cudagraph_capture_size": 1024,
    "gpu_memory_utilization": 0.9,
    "speculative_config": {
      "method": "dspark",
      "num_speculative_tokens": 5,
      "draft_sample_method": "probabilistic",
      "rejection_sample_method": "block",
      "enable_adaptive_verification": false
    },
    "reasoning_parser": "deepseek_v41",
    "default_chat_template_kwargs": {
      "thinking": true,
      "reasoning_effort": 50
    },
    "tool_call_parser": "deepseek_v41",
    "enable_auto_tool_choice": true,
    "language_model_only": true,
    "disable_uvicorn_access_log": true
  },
  "deployment": {
    "nodes": 1,
    "gpus_per_node": 8,
    "node_ips": ["10.0.0.10"],
    "distributed_executor_backend": "local"
  },
  "container": {
    "image": "vllm/vllm-openai:deepseekv41-flash-0909",
    "environment": {
      "VLLM_ENGINE_READY_TIMEOUT_S": "3600",
      "VLLM_USE_RUST_FRONTEND": "1"
    },
    "mounts": [
      {
        "host_path": "/models/DeepSeek-V4.1-Flash",
        "container_path": "/models/DeepSeek-V4.1-Flash",
        "read_only": true
      }
    ],
    "shm_size": "32g",
    "network_host": true,
    "name_prefix": "dsv41"
  },
  "extras": {
    "serve_args": [],
    "docker_args": []
  },
  "warnings": []
}
```

约定：

- `serve` 的键名就是 vLLM 参数名。除 `model`（位置参数）、`pipeline_parallel_size: 1`（vLLM 默认值，渲染时省略）、`distributed_executor_backend: "local"`（单机不传旗标）外，**键出现即表示要传对应旗标**（snake_case → `--kebab-case`）。
- 布尔旗标只在 `true` 时出现；可选参数未设置时直接省略（如 `api_key`、`max_num_seqs`、`enforce_eager`）。
- `speculative_config` / `default_chat_template_kwargs` 保持结构化对象，阶段 2 才序列化为 JSON。
- `thinking` 映射为 `reasoning_parser` + `default_chat_template_kwargs`；tool calling 映射为 `tool_call_parser` + `enable_auto_tool_choice`；multimodal 映射为 `mm_encoder_tp_mode` 或 `language_model_only`。不再有 `features` 抽象层。
- Jsonnet 的 JSON 浮点输出可能带长尾（例如 `0.90000000000000002`），值等价于 `0.9`；阶段 2 渲染 argv 时会格式化为 `0.9`。
- 设置了 `apiKey` 时，`serve.api_key` 会以明文写入参数产物；`vllm/out/` 已被 `.gitignore` 忽略，请勿提交带密钥的产物。

### `serve` 键名 ↔ vLLM 旗标

| 参数产物键 | vLLM 旗标 |
| --- | --- |
| `model` | `vllm serve <model>`（位置参数） |
| `served_model_name` | `--served-model-name` |
| `tokenizer_mode` | `--tokenizer-mode` |
| `host` | `--host` |
| `port` | `--port` |
| `api_key` | `--api-key` |
| `tensor_parallel_size` | `--tensor-parallel-size` |
| `pipeline_parallel_size` | `--pipeline-parallel-size`（值为 1 时省略） |
| `enable_expert_parallel` | `--enable-expert-parallel` |
| `max_model_len` | `--max-model-len` |
| `max_num_batched_tokens` | `--max-num-batched-tokens` |
| `max_cudagraph_capture_size` | `--max-cudagraph-capture-size` |
| `gpu_memory_utilization` | `--gpu-memory-utilization` |
| `max_num_seqs` | `--max-num-seqs` |
| `speculative_config` | `--speculative-config`（JSON） |
| `reasoning_parser` | `--reasoning-parser` |
| `default_chat_template_kwargs` | `--default-chat-template-kwargs`（JSON） |
| `tool_call_parser` | `--tool-call-parser` |
| `enable_auto_tool_choice` | `--enable-auto-tool-choice` |
| `language_model_only` | `--language-model-only` |
| `mm_encoder_tp_mode` | `--mm-encoder-tp-mode` |
| `disable_uvicorn_access_log` | `--disable-uvicorn-access-log` |
| `enforce_eager` | `--enforce-eager` |

### `deployment` 与逐机参数

| 产物键 | 阶段 2 渲染 |
| --- | --- |
| `nodes` | mp: `--nnodes`；Ray: `ray start` 的节点数 |
| `gpus_per_node` | Ray: `ray start --num-gpus` |
| `node_ips` | `--node-ip-address`、mp 的 `--master-addr` |
| `distributed_executor_backend` | `--distributed-executor-backend`（`local` 时省略） |
| `ray_port` | `ray start --port` / worker 的 `--address` |
| `master_port` | mp 的 `--master-port` |

## 阶段 2 产物：`vllm-cli/v1`

```jsonc
{
  "apiVersion": "vllm-cli/v1",
  "meta": {
    "sourceApiVersion": "vllm-params/v1",
    "scenario": "单机 8×H200：..."
  },
  "cli": {
    "serve": {
      "model": "/models/DeepSeek-V4.1-Flash",
      "servedModelName": "deepseek-ai/DeepSeek-V4.1-Flash",
      "argv": ["vllm", "serve", "..."],
      "command": "vllm serve ..."
    },
    "deployment": {
      "mode": "single-node",
      "nodes": [
        {
          "rank": 0,
          "role": "server",
          "ip": "10.0.0.10",
          "env": { "...": "..." },
          "innerCommand": "...",
          "serve": { "argv": [], "command": "" },
          "ray": null,
          "docker": { "argv": [], "command": "" },
          "command": "docker run ..."
        }
      ],
      "commands": ["docker run ..."]
    }
  },
  "warnings": []
}
```

- `cli.serve.argv` 是 exec 形式（每个 token 一个元素），适合程序直接消费；
- `cli.serve.command` 和 `cli.deployment.nodes[].command` 是 shell 形式，已做单引号转义，可直接复制执行；
- `cli.deployment.nodes[].docker.argv` 也是 exec 形式；
- 直接执行 `cli.serve.command` 前需要自行注入 `container.environment` 中的变量；`cli.deployment.nodes[].command` 已通过 `docker run -e` 注入；
- 单机 `mode` 为 `single-node`；Ray 多机为 `ray-multi-node`；mp 多机为 `mp-multi-node`；
- Ray worker 的 `serve` 为 `null`，非 Ray 的 `ray` 为 `null`。

## 多机部署

### 1. Ray 后端（默认）

```bash
jsonnet vllm/generate-params.jsonnet \
  --tla-code-file config=vllm/params/multi-h200-2x8-ray.json \
  > vllm/out/ray.params.json

jsonnet vllm/render-cli.jsonnet \
  --tla-code-file params=vllm/out/ray.params.json \
  > vllm/out/ray.cli.json
```

`cli.deployment.nodes[]` 中：

- **head（rank 0）**：

  ```bash
  ray start --head --port=6379 --node-ip-address=10.0.0.10 --num-gpus=8 --disable-usage-stats \
    && vllm serve ... --distributed-executor-backend ray
  ```

- **worker（rank 1..N-1）**：

  ```bash
  ray start --address=10.0.0.10:6379 --node-ip-address=10.0.0.11 --num-gpus=8 --block --disable-usage-stats
  ```

启动顺序：

1. 先执行 head 的命令（先起 Ray head，再启动 vLLM；vLLM 会等待集群资源）；
2. 再在其他机器执行各自的 worker 命令；
3. `VLLM_ENGINE_READY_TIMEOUT_S=3600` 给了足够长的等待时间；vLLM 的 Ray placement group 默认等待 1800 秒，请在这个时间内把 worker 起齐。

注意：

- Ray 模式下**不要**传 `--nnodes`。vLLM 0.31 只允许 `mp` / `uni` / `external_launcher` 后端使用 `--nnodes`；Ray 后端通过集群资源发现节点；
- 多机建议 `container.network_host: true`，否则 Ray / NCCL 的动态端口需要额外映射；
- 所有机器的镜像、模型路径、Ray 版本应保持一致。

### 2. mp 后端（vLLM 原生 `--nnodes`）

```bash
jsonnet vllm/generate-params.jsonnet \
  --tla-code-file config=vllm/params/multi-h200-2x8-mp-tp16.json \
  > vllm/out/mp.params.json

jsonnet vllm/render-cli.jsonnet \
  --tla-code-file params=vllm/out/mp.params.json \
  > vllm/out/mp.cli.json
```

- **head（rank 0）**：

  ```bash
  vllm serve ... \
    --distributed-executor-backend mp \
    --nnodes 2 --node-rank 0 \
    --master-addr 10.0.0.10 --master-port 29501
  ```

- **worker（rank 1..N-1）**：

  ```bash
  vllm serve ... \
    --headless \
    --distributed-executor-backend mp \
    --nnodes 2 --node-rank 1 \
    --master-addr 10.0.0.10 --master-port 29501
  ```

启动顺序：先在 head 启动，再启动 worker；所有节点通过 `master-addr:master-port` 完成 rendezvous。mp 模式不依赖 Ray。

## 功能开关映射

| 开关 | 参数产物 | 生成的 vLLM 参数 |
| --- | --- | --- |
| `speculative: true` | `speculative_config` | `--speculative-config '{"method":"dspark",...}'` |
| `speculative: false` | 省略该键 | 省略 `--speculative-config` |
| `thinking: true` | `reasoning_parser` + `default_chat_template_kwargs` | `--reasoning-parser deepseek_v41` + `--default-chat-template-kwargs '{"thinking":true,"reasoning_effort":50}'` |
| `thinking: false` 或 `reasoningEffort: "none"` | 省略 `reasoning_parser`，kwargs 为 false/none | `--default-chat-template-kwargs '{"thinking":false,"reasoning_effort":"none"}'` |
| `toolCalling: true` | `tool_call_parser` + `enable_auto_tool_choice` | `--tool-call-parser deepseek_v41 --enable-auto-tool-choice` |
| `toolCalling: false` | 省略上述两个键 | 省略对应参数 |
| `multimodal: false` | `language_model_only: true` | `--language-model-only` |
| `multimodal: true` | `mm_encoder_tp_mode: "data"` | `--mm-encoder-tp-mode data` |
| `reasoningEffort: "low" / "high" / "xhigh" / "max"` | 归一化为 `25 / 50 / 75 / 100` | 写入 `reasoning_effort` |
| `reasoningEffort: 1..100` | 原样写入 | 写入 `reasoning_effort` |

请求级覆盖示例（服务端已启动）：

```python
from openai import OpenAI

client = OpenAI(base_url="http://10.0.0.10:8000/v1", api_key="EMPTY")

resp = client.chat.completions.create(
    model="deepseek-ai/DeepSeek-V4.1-Flash",
    messages=[{"role": "user", "content": "17*19 等于多少？只返回整数。"}],
    extra_body={
        "chat_template_kwargs": {
            "thinking": True,
            "reasoning_effort": 25,
        }
    },
)
print(resp.choices[0].message.content)
```

## 示例参数文件

| 文件 | 机器 × 卡数 | 并行 | 后端 | 说明 |
| --- | --- | --- | --- | --- |
| `single-h200-8gpu.json` | 1 × 8 | TP8 | 单机 | DSpark / thinking / tool calling 全开，effort=50 |
| `single-h200-8gpu-switches-off.json` | 1 × 8 | TP8 | 单机 | 关闭投机 / thinking / tool calling，开启多模态 |
| `single-gb200-4gpu.json` | 1 × 4 | TP4 | 单机 | GB200 NVL4，effort=100 |
| `multi-h200-2x8-ray.json` | 2 × 8 | TP8 × PP2 | Ray | 机内 TP、机间 PP |
| `multi-h200-2x8-mp-tp16.json` | 2 × 8 | TP16 | mp | 跨机 TP，原生 `--nnodes`；用 `totalGpus: 16` 推导每机 8 卡 |

## 校验与测试

> **范围**：本项目是 demo/原型验证，不是生产级部署工具。测试只要求两阶段端到端可跑、golden 命令等价、文档/路径可用；不要扩展为安全加固、模糊测试、性能或完整 CI。验证以 `./vllm/run-tests.sh`、`jsonnetfmt --test`、`bash -n` 为准，其他问题记录为 nit 即可。

```bash
# 阶段 1 断言（含 validate 负例）
jsonnet vllm/params-tests.jsonnet

# 阶段 2 断言（含 schema 负例）
jsonnet vllm/cli-tests.jsonnet

# 新旧 CLI 投影等价性（对比改造前冻结的 5 场景基线）
jsonnet vllm/golden-tests.jsonnet

# 三层测试 + 所有场景的两阶段渲染
./vllm/run-tests.sh

# 格式化检查
jsonnetfmt --test \
  vllm/generate-params.jsonnet vllm/render-cli.jsonnet \
  vllm/lib/params.libsonnet vllm/lib/cli.libsonnet vllm/lib/parallel.libsonnet \
  vllm/params-tests.jsonnet vllm/cli-tests.jsonnet vllm/golden-tests.jsonnet

# shell 语法检查
bash -n vllm/render-params.sh vllm/render-cli.sh vllm/run-tests.sh
```

`vllm/tests/golden/legacy-render.json` 是改造前用旧 `main.jsonnet` 生成的 5 场景基线，用于确保新流程的 `cli.serve`、`cli.deployment`、`warnings` 与原命令文本完全一致。只有确认要改变命令行为时才更新该 fixture。

非法输入会直接报错，例如：

```bash
jsonnet vllm/generate-params.jsonnet --tla-code config='{nodes: 2, gpusPerNode: 8, tensorParallel: 5}'
# RUNTIME ERROR: TP × PP 必须等于总卡数：5 × 2 != 2 机 × 8 卡 = 16
```

## 注意事项

1. **模型规模**：DeepSeek-V4.1-Flash 是 552B 主干 + 196B Engram 的 vision-language MoE，量化权重约 511 GB；官方给出的显存下限约 614 GB。单机 8×H200 或 GB200 NVL4 是已验证起点。
2. **1M 上下文**：默认 `maxModelLen=1048576`。实际可用长度取决于显存、`maxNumBatchedTokens`、并发和 prefix caching，建议先用小并发压测再放大。
3. **thinking 默认开启**：官方默认 thinking=true、effort=50。如果客户端 `max_tokens` 设得太小，预算可能全部花在思考链上，表现为 `content` 为空、`finish_reason=length`。可以显式关闭 thinking 或放宽预算。
4. **工具调用格式**：V4.1 使用 DSML 标签，解析器名为 `deepseek_v41`，与 V4 的格式不完全兼容；不要混用旧的 `deepseek_v3` 解析器。
5. **纯文本 vs 多模态**：`language_model_only: true` 会跳过视觉编码器，适合纯文本负载；需要图片输入时把 `multimodal` 设为 `true`，产物改为 `mm_encoder_tp_mode`。
6. **Docker 网络**：多机建议 `network_host: true`。单机调试可设 `dockerNetworkHost: false`，阶段 2 会改用 `-p` 端口映射。
7. **模型路径**：示例参数使用容器路径 `/models/DeepSeek-V4.1-Flash`。请把 `modelHostPath` 改成宿主机上的实际模型目录，并保持 `modelPath` 为容器内路径。
8. **镜像与版本**：V4.1 需要专用镜像 `vllm/vllm-openai:deepseekv41-flash-0909` 与 vLLM >= 0.31.0；普通 pip 版本可能不包含 V4.1 架构支持。
9. **跨机 TP**：对 IB / RoCE 和 NCCL 配置敏感。没有高速互联时，优先用 `parallelMode: "tp-pp"`（机内 TP、机间 PP）。
10. **密钥**：设置 `apiKey` 后，`serve.api_key` 会以明文写入参数产物。不要把带真实密钥的产物提交到仓库；`vllm/out/` 已被 `.gitignore` 忽略。
11. **中间产物**：`vllm/out/*.params.json` 和 `vllm/out/*.cli.json` 都是运行产物，不需要提交；参数产物可以单独保存、审阅或交给其他工具消费。
12. **浮点显示**：Jsonnet 的 JSON 浮点可能显示为 `0.90000000000000002`，等价于 `0.9`；阶段 2 渲染 argv 时会用 `%.10g` 格式化。

## 参考

- [vLLM recipe：deepseek-ai/DeepSeek-V4.1-Flash](https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash)
- [HuggingFace：DeepSeek-V4.1-Flash](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- [vLLM Multi-Node Serving（Ray）](https://docs.vllm.ai/en/v0.31.0/examples/ray_serving/multi-node-serving/)
- [vLLM Data Parallel Deployment（DP 扩展参考）](https://docs.vllm.ai/en/v0.31.0/serving/data_parallel_deployment.html)
- [vLLM DeepSeek-V4.1 tokenizer 文档](https://docs.vllm.ai/en/latest/api/vllm/tokenizers/deepseek_v41/)
- [vLLM Blog：DeepSeek-V4.1-Flash on vLLM](https://vllm.ai/blog/2026-10-23-deepseek-v41-flash-pd-wide-ep)
- [DeepSeek V4.1 Flash 部署完整指南（第三方）](https://news.qiniu.com/archives/1789024203476)
