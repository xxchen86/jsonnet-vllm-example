# DeepSeek-V4.1-Flash × vLLM 启动参数模板（Jsonnet）

把 [vLLM 官方 recipe](https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash) 的 `vllm serve` 参数收敛成一份 Jsonnet 模板：

- **卡数驱动并行**：外部传入 `gpusPerNode`，自动推导 TP / PP；
- **机器数驱动分布式**：外部传入 `nodes`，生成 Ray 或 mp 后端的逐机命令；
- **开关驱动参数**：外部传入 `speculative` / `thinking` / `toolCalling` / `multimodal`，按开关生成或省略对应参数；
- **直接可执行**：输出同时包含结构化 JSON、`argv` 数组和可复制执行的逐机 Docker 命令。

> 目标镜像：`vllm/vllm-openai:deepseekv41-flash-0909`（要求 vLLM >= 0.31.0）。
> 模型权重约 511 GB（含 196B Engram 记忆表），官方建议至少 614 GB 显存（511 GB × 1.2）。

## 目录

```text
vllm/
├── main.jsonnet                  # 入口：function(config={})，用 --tla-code-file 注入参数
├── lib/
│   ├── parallel.libsonnet        # TP/PP 推导、校验、每机 IP 生成
│   └── serve.libsonnet           # vLLM 参数、功能开关、Docker / Ray / mp 命令
├── params/
│   ├── single-h200-8gpu.json             # 1 机 × 8 卡，TP8，功能全开
│   ├── single-h200-8gpu-switches-off.json # 1 机 × 8 卡，关闭投机/thinking/tool，开多模态
│   ├── single-gb200-4gpu.json            # 1 机 × 4 卡，TP4
│   ├── multi-h200-2x8-ray.json           # 2 机 × 8 卡，TP8 × PP2，Ray
│   └── multi-h200-2x8-mp-tp16.json       # 2 机 × 8 卡，TP16，mp + --nnodes
├── tests.jsonnet                 # 断言测试
├── render.ps1                    # 渲染脚本（输出 JSON / YAML）
└── run-tests.ps1                 # 跑断言 + 渲染全部参数文件
```

## 快速开始

```powershell
# 1. 直接渲染到终端（默认单机 8×H200）
jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/single-h200-8gpu.json

# 2. 用脚本写入文件（UTF-8 无 BOM）
powershell -ExecutionPolicy Bypass -File vllm/render.ps1 -Config vllm/params/single-h200-8gpu.json -OutFile vllm/out/single.json

# 3. 渲染多机 Ray 场景
powershell -ExecutionPolicy Bypass -File vllm/render.ps1 -Config vllm/params/multi-h200-2x8-ray.json

# 4. 输出 YAML
powershell -ExecutionPolicy Bypass -File vllm/render.ps1 -Config vllm/params/single-h200-8gpu.json -Yaml
```

也可以直接内联覆盖：

```powershell
jsonnet vllm/main.jsonnet --tla-code config='{nodes: 2, gpusPerNode: 8, speculative: true}'
```

不带任何参数时，入口会使用默认值（单机 8×H200、TP8、thinking / DSpark / tool calling 全开）。

## 输入参数

### 核心字段

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `nodes` | `1` | 机器数量 |
| `totalGpus` | `null` | 可选：总卡数；设置后按 `nodes` 推导每机卡数，必须能被 `nodes` 整除 |
| `gpusPerNode` | `8` | 每台机器的 GPU 数；与 `totalGpus` 同时设置且冲突时报错 |
| `gpuMemoryGiB` | `141` | 单卡显存（H200=141，H100=80，B200/GB200=192），仅用于显存下限提示 |
| `modelLayers` | `40` | 模型层数，仅用于 PP 整除性提示 |
| `parallelMode` | `"auto"` | `auto` / `tp` / `tp-pp`，见下一节 |
| `tensorParallel` | `null` | 显式指定 TP，覆盖推导值 |
| `pipelineParallel` | `null` | 显式指定 PP，覆盖推导值 |
| `expertParallel` | `true` | TP > 1 时追加 `--enable-expert-parallel` |
| `distributedBackend` | `"ray"` | 多机后端：`ray` 或 `mp`；单机忽略 |
| `nodeIpPattern` | `"10.0.0.%d"` | 按机器序号格式化 IP |
| `nodeIpStart` | `10` | IP 起始值，配合 `nodeIpPattern` |
| `nodeIps` | `[]` | 显式 IP 列表；非空时优先于 `nodeIpPattern` |
| `rayPort` | `6379` | Ray head 端口 |
| `masterPort` | `29501` | mp 后端 rendezvous 端口 |

> `expertParallel` 默认开启（TP > 1 时生效）；如果遇到 EP 后端兼容性问题，可设为 `false` 回退到纯 TP。

### 功能开关

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `speculative` | `true` | `true` / `false`，或对象（见下） |
| `thinking` | `true` | 是否默认开启思考 |
| `reasoningEffort` | `50` | `1-100` 整数，或 `low` / `high` / `xhigh` / `max` / `none` |
| `toolCalling` | `true` | `true` / `false`，或 `{enabled, parser}` |
| `multimodal` | `false` | `false` 生成 `--language-model-only`；`true` 生成 `--mm-encoder-tp-mode data` |
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
| `modelPath` | `null` | 容器内模型路径；设置后优先于 `model` |
| `modelHostPath` | `null` | 宿主机模型目录；与 `modelPath` 同时设置时自动 `-v ...:ro` |
| `image` | `"vllm/vllm-openai:deepseekv41-flash-0909"` | vLLM 镜像 |
| `host` / `port` | `"0.0.0.0"` / `8000` | HTTP 监听地址 |
| `apiKey` | `null` | 设置后追加 `--api-key`（注意不要把真实密钥提交到仓库） |
| `maxModelLen` | `1048576` | 官方 recipe 的 1M 上下文 |
| `maxNumBatchedTokens` | `16384` | 官方 recipe 默认 |
| `maxCudagraphCaptureSize` | `1024` | 官方 recipe 默认 |
| `gpuMemoryUtilization` | `0.9` | 官方 recipe 默认 |
| `maxNumSeqs` | `null` | 不设置则用 vLLM 默认 |
| `enforceEager` | `false` | 调试时可设为 `true`，追加 `--enforce-eager` |
| `disableUvicornAccessLog` | `true` | 追加 `--disable-uvicorn-access-log` |
| `dockerShmSize` | `"32g"` | Docker `--shm-size` |
| `dockerNetworkHost` | `true` | 多机建议保持 `true`（`--network host`） |
| `hfHubOffline` | `false` | 设为 `true` 时追加 `HF_HUB_OFFLINE=1` |

### 逃生舱

| 字段 | 说明 |
| --- | --- |
| `extraEnv` | 追加/覆盖容器环境变量 |
| `extraMounts` | 追加挂载，元素形如 `{hostPath, containerPath, readOnly}` |
| `extraDockerArgs` | 追加到 `docker run` 的参数（字符串数组） |
| `extraArgs` | 追加到 `vllm serve` 末尾的参数（字符串数组） |

## 并行推导

设 `N = nodes`、`G = gpusPerNode`、总卡数 `W = N × G`。

| `parallelMode` | 单机（N=1） | 多机（N>1） |
| --- | --- | --- |
| `auto` | `TP=G`, `PP=1` | `TP=G`, `PP=N` |
| `tp` | `TP=G`, `PP=1` | `TP=N×G`, `PP=1` |
| `tp-pp` | `TP=G`, `PP=1` | `TP=G`, `PP=N` |

约束与提示：

- 必须满足 `TP × PP == W`，否则直接报错；
- 卡数可以传 `totalGpus`（总卡数）或 `gpusPerNode`（每机卡数）；`totalGpus` 必须能被 `nodes` 整除，两者同时显式设置且冲突时报错；
- 显式传入 `tensorParallel` / `pipelineParallel` 时优先使用显式值，但仍要满足上面的等式；
- 模型共 40 层，PP 建议取 40 的约数（1/2/4/5/8/10/20/40）。例如 3 机 `auto` 会得到 `PP=3`，模板会给出警告，建议改用 `parallelMode: "tp"`；
- 总显存低于 614 GB 时会给出警告，但不会阻止渲染。

> 本模板聚焦 TP / PP；如果需要 DEP（DP + EP）高吞吐模式，可参考 [vLLM Data Parallel Deployment](https://docs.vllm.ai/en/v0.31.0/serving/data_parallel_deployment.html)，在参数中加入 `--data-parallel-size` 等选项。

常见组合：

| 场景 | 配置 | 结果 |
| --- | --- | --- |
| 单机 8 卡 | `nodes=1, gpusPerNode=8` | `TP8 × PP1` |
| 单机 4 卡 | `nodes=1, gpusPerNode=4` | `TP4 × PP1` |
| 2 机 × 8 卡，机内 TP | `nodes=2, parallelMode="tp-pp"` | `TP8 × PP2` |
| 2 机 × 8 卡，跨机 TP | `nodes=2, parallelMode="tp"` | `TP16 × PP1` |
| 4 机 × 4 卡，跨机 TP | `nodes=4, gpusPerNode=4, parallelMode="tp"` | `TP16 × PP1` |

只传总卡数也可以：

```powershell
jsonnet vllm/main.jsonnet --tla-code config='{nodes: 2, totalGpus: 16, parallelMode: "tp"}'
```

## 多机部署

多机有两种后端，模板会生成对应的逐机命令。所有命令都在 `deployment.nodes[]` 中，每个节点一个 `command`，并附带 `docker.argv`（exec 形式）和 `docker.command`（shell 形式）。

### 1. Ray 后端（默认，官方多机示例用法）

先生成配置：

```powershell
jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/multi-h200-2x8-ray.json
```

生成的节点命令：

- **head（node 0）**：

  ```bash
  ray start --head --port=6379 --node-ip-address=10.0.0.10 --num-gpus=8 --disable-usage-stats \
    && vllm serve ... --distributed-executor-backend ray
  ```

- **worker（node 1..N-1）**：

  ```bash
  ray start --address=10.0.0.10:6379 --node-ip-address=10.0.0.11 --num-gpus=8 --block --disable-usage-stats
  ```

启动顺序：

1. 先执行 head 的命令（它会先起 Ray head，再启动 vLLM；vLLM 会等待集群资源）；
2. 再在其他机器执行各自的 worker 命令；
3. `VLLM_ENGINE_READY_TIMEOUT_S=3600` 给了足够长的等待时间；vLLM 的 Ray placement group 默认等待 1800 秒，请在这个时间内把 worker 起齐。

注意：

- Ray 模式下**不要**传 `--nnodes`。vLLM 0.31 只允许 `mp` / `uni` / `external_launcher` 后端使用 `--nnodes`；Ray 后端通过集群资源发现节点；
- 多机建议 `dockerNetworkHost: true`，否则 Ray / NCCL 的动态端口需要额外映射；
- 所有机器的镜像、模型路径、Ray 版本应保持一致。

### 2. mp 后端（vLLM 原生 `--nnodes`）

```powershell
jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/multi-h200-2x8-mp-tp16.json
```

生成的节点命令：

- **head（node 0）**：

  ```bash
  vllm serve ... \
    --distributed-executor-backend mp \
    --nnodes 2 --node-rank 0 \
    --master-addr 10.0.0.10 --master-port 29501
  ```

- **worker（node 1..N-1）**：

  ```bash
  vllm serve ... \
    --headless \
    --distributed-executor-backend mp \
    --nnodes 2 --node-rank 1 \
    --master-addr 10.0.0.10 --master-port 29501
  ```

启动顺序：先在 head 启动，再启动 worker；所有节点通过 `master-addr:master-port` 完成 rendezvous。mp 模式不依赖 Ray。

## 功能开关映射

| 开关 | 生成的 vLLM 参数 |
| --- | --- |
| `speculative: true` | `--speculative-config '{"method":"dspark","num_speculative_tokens":5,"draft_sample_method":"probabilistic","rejection_sample_method":"block","enable_adaptive_verification":false}'` |
| `speculative: false` | 省略 `--speculative-config` |
| `thinking: true` | `--reasoning-parser deepseek_v41` + `--default-chat-template-kwargs '{"thinking":true,"reasoning_effort":50}'` |
| `thinking: false` 或 `reasoningEffort: "none"` | 省略 `--reasoning-parser`，并生成 `--default-chat-template-kwargs '{"thinking":false,"reasoning_effort":"none"}'` |
| `toolCalling: true` | `--tool-call-parser deepseek_v41 --enable-auto-tool-choice` |
| `toolCalling: false` | 省略上述两个参数 |
| `multimodal: false` | `--language-model-only`（跳过视觉编码器，省显存） |
| `multimodal: true` | 省略 `--language-model-only`，生成 `--mm-encoder-tp-mode data`（可用 `mmEncoderTpMode` 改为 `weights`） |
| `reasoningEffort: "low" / "high" / "xhigh" / "max"` | 分别归一化为 `25 / 50 / 75 / 100` |
| `reasoningEffort: 1..100` | 原样写入 `reasoning_effort` |

> `--reasoning-parser` 与 thinking 开关绑定：关闭 thinking 时不注册解析器。如果希望请求级临时开启 thinking，请保持 `thinking: true`，再在请求里覆盖 `chat_template_kwargs`。

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

## 输出结构

```jsonc
{
  "parallel": {
    "description": "TP8 × PP2（2 机 × 8 卡 = 16 卡）",
    "tensorParallel": 8,
    "pipelineParallel": 2,
    "expertParallel": true
  },
  "distributed": {
    "backend": "ray",
    "multiNode": true,
    "nodeIps": ["10.0.0.10", "10.0.0.11"],
    "headAddress": "10.0.0.10",
    "rayPort": 6379
  },
  "features": {
    "speculative": { "enabled": true, "method": "dspark" },
    "thinking": { "enabled": true, "reasoningEffort": 50 },
    "toolCalling": { "enabled": true, "parser": "deepseek_v41" },
    "multimodal": { "enabled": false, "languageModelOnly": true }
  },
  "serve": {
    "model": "/models/DeepSeek-V4.1-Flash",
    "argv": ["vllm", "serve", "..."],
    "command": "vllm serve ..."
  },
  "deployment": {
    "mode": "ray-multi-node",
    "nodes": [
      {
        "rank": 0,
        "role": "head",
        "ip": "10.0.0.10",
        "innerCommand": "ray start --head ... && vllm serve ...",
        "docker": { "argv": ["docker", "run", "..."], "command": "docker run ..." },
        "command": "docker run ..."
      }
    ]
  },
  "warnings": []
}
```

- `serve.argv` 是 exec 形式（每个 token 一个元素），适合程序直接消费；
- `serve.command` 和 `deployment.nodes[].command` 是 shell 形式，已做单引号转义，可直接复制执行；
- `deployment.nodes[].docker.argv` 也是 exec 形式；
- 直接执行 `serve.command` 前需要自行注入 `environment` 中的变量；`deployment.nodes[].command` 已通过 `docker run -e` 注入；
- 单机配置的 `deployment.mode` 为 `single-node`，`distributed.backend` 为 `local`，没有 Ray 对象。

## 示例参数文件

| 文件 | 机器 × 卡数 | 并行 | 后端 | 说明 |
| --- | --- | --- | --- | --- |
| `single-h200-8gpu.json` | 1 × 8 | TP8 | 单机 | DSpark / thinking / tool calling 全开，effort=50 |
| `single-h200-8gpu-switches-off.json` | 1 × 8 | TP8 | 单机 | 关闭投机 / thinking / tool calling，开启多模态 |
| `single-gb200-4gpu.json` | 1 × 4 | TP4 | 单机 | GB200 NVL4，effort=100 |
| `multi-h200-2x8-ray.json` | 2 × 8 | TP8 × PP2 | Ray | 机内 TP、机间 PP |
| `multi-h200-2x8-mp-tp16.json` | 2 × 8 | TP16 | mp | 跨机 TP，原生 `--nnodes`；用 `totalGpus: 16` 推导每机 8 卡 |

## 校验与测试

```powershell
# 断言测试：TP/PP、开关映射、警告、Ray/mp 命令
jsonnet vllm/tests.jsonnet

# 断言测试 + 渲染所有 params
powershell -ExecutionPolicy Bypass -File vllm/run-tests.ps1

# 格式化检查
jsonnetfmt --test vllm/main.jsonnet vllm/lib/parallel.libsonnet vllm/lib/serve.libsonnet vllm/tests.jsonnet
```

非法输入会直接报错，例如：

```powershell
jsonnet vllm/main.jsonnet --tla-code config='{nodes: 2, gpusPerNode: 8, tensorParallel: 5}'
# RUNTIME ERROR: TP × PP 必须等于总卡数：5 × 2 != 2 机 × 8 卡 = 16
```

## 注意事项

1. **模型规模**：DeepSeek-V4.1-Flash 是 552B 主干 + 196B Engram 的 vision-language MoE，量化权重约 511 GB；官方给出的显存下限约 614 GB。单机 8×H200 或 GB200 NVL4 是已验证起点。
2. **1M 上下文**：默认 `maxModelLen=1048576`。实际可用长度取决于显存、`maxNumBatchedTokens`、并发和 prefix caching，建议先用小并发压测再放大。
3. **thinking 默认开启**：官方默认 thinking=true、effort=50。如果客户端 `max_tokens` 设得太小，预算可能全部花在思考链上，表现为 `content` 为空、`finish_reason=length`。可以显式关闭 thinking 或放宽预算。
4. **工具调用格式**：V4.1 使用 DSML 标签，解析器名为 `deepseek_v41`，与 V4 的格式不完全兼容；不要混用旧的 `deepseek_v3` 解析器。
5. **纯文本 vs 多模态**：`--language-model-only` 会跳过视觉编码器，适合纯文本负载；需要图片输入时把 `multimodal` 设为 `true`，模板会改为 `--mm-encoder-tp-mode data`。
6. **Docker 网络**：多机建议 `--network host`。Windows Docker Desktop 对 host 网络支持因版本而异；单机调试可设 `dockerNetworkHost: false`，模板会改用 `-p 8000:8000`。
7. **模型路径**：示例参数使用 Linux 容器路径 `/models/DeepSeek-V4.1-Flash`。在 Windows 上请把 `modelHostPath` 改成类似 `D:/models/DeepSeek-V4.1-Flash`，并保持 `modelPath` 为容器内路径。
8. **镜像与版本**：V4.1 需要专用镜像 `vllm/vllm-openai:deepseekv41-flash-0909` 与 vLLM >= 0.31.0；普通 pip 版本可能不包含 V4.1 架构支持。
9. **跨机 TP**：对 IB / RoCE 和 NCCL 配置敏感。没有高速互联时，优先用 `parallelMode: "tp-pp"`（机内 TP、机间 PP）。
10. **密钥**：设置 `apiKey` 后，渲染结果会包含 `--api-key`。不要把带真实密钥的输出提交到仓库。

## 参考

- [vLLM recipe：deepseek-ai/DeepSeek-V4.1-Flash](https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash)
- [HuggingFace：DeepSeek-V4.1-Flash](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
- [vLLM Multi-Node Serving（Ray）](https://docs.vllm.ai/en/v0.31.0/examples/ray_serving/multi-node-serving/)
- [vLLM Data Parallel Deployment（DP 扩展参考）](https://docs.vllm.ai/en/v0.31.0/serving/data_parallel_deployment.html)
- [vLLM DeepSeek-V4.1 tokenizer 文档](https://docs.vllm.ai/en/latest/api/vllm/tokenizers/deepseek_v41/)
- [vLLM Blog：DeepSeek-V4.1-Flash on vLLM](https://vllm.ai/blog/2026-10-23-deepseek-v41-flash-pd-wide-ep)
- [DeepSeek V4.1 Flash 部署完整指南（第三方）](https://news.qiniu.com/archives/1789024203476)
