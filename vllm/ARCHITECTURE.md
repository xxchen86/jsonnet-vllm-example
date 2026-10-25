# vLLM 静态模板与动态 INPUT：核心架构与模块契约

本文只记录核心架构、关键模块和模块间契约中**不变**的部分。实现细节、profile 的可选字段、辅助函数的内部结构、具体文案等可以演进，不在此列。

## 0. 术语

| 术语 | 指代 |
| --- | --- |
| **静态模板** | 可复用的 Jsonnet 函数或 `vllm-params/v1` 对象，决定“如何生成参数”；包括它引用的 profiles、辅助函数和自动化模块。原“启动声明”。 |
| **动态 INPUT** | 每次部署传入的扁平部分覆盖对象，`vllm/params/*.json` 或 `--tla-code config=...`；决定“这次部署的具体值”。原“场景 config”。 |
| **参数产物** | 阶段 1 的输出 `vllm-params/v1`。 |
| **CLI 产物** | 阶段 2 的输出 `vllm-cli/v1`。 |

## 1. 总览

```text
动态 INPUT ──────────────┐
                         ├─> 静态模板求值 ─> vllm-params/v1 ─> vllm-cli/v1
静态模板（templates/*）──┘
```

- **阶段 1**：静态模板 + 动态 INPUT → `vllm-params/v1`。
- **阶段 2**：`vllm-params/v1` → `vllm-cli/v1`。
- 静态模板分两种写法，共用同一 Jsonnet 语法和同一产物 schema：
  - **高层**：调用 `launch-helpers.libsonnet`，使用 profile 与 `ctx.automation.*`；
  - **底层**：直接写 `vllm-params/v1` 字面量，或把一份 v1 产物当静态模板。
- 两者可以混用；区别只在“是否调用辅助函数”。
- 不存在独立的 `vllm-launch-template/v1` 产物；静态模板就是 Jsonnet 声明，唯一产物版本是 `vllm-params/v1`。

## 2. 阶段边界（硬约束）

| 约束 | 说明 |
| --- | --- |
| 阶段 1 只产出 v1 | 不生成 argv、shell 命令、Docker / Ray / mp 命令 |
| 阶段 2 只消费 v1 | 不 import `launch` / `launch-helpers` / 静态模板 / 自动化模块 |
| 阶段 2 不做默认值与推导 | 不读取动态 INPUT，不推导 TP / PP，不合并 profile |
| `errors` 不进入最终产物 | 静态模板结果可携带 `errors`，`generate` 会剥离 |
| 版本精确匹配 | 阶段 1 只认 `vllm-params/v1`，阶段 2 只认 `vllm-params/v1` / 输出 `vllm-cli/v1` |

阶段 2 的独立性是核心不变量：任何保存下来的 `vllm-params/v1` 产物都可以在没有静态模板、profile、动态 INPUT 的情况下单独渲染。

## 3. 关键模块

```text
generate-params.jsonnet
  ├─> launch.libsonnet                 # 静态模板引擎
  └─> templates/<静态模板>              # 函数或 v1 对象
        ├─> launch-helpers.libsonnet   # 可选高层辅助 + 自动化模块
        │     └─> parallel.libsonnet   # 纯 TP/PP 规划
        └─> profiles/*                 # 纯数据

render-cli.jsonnet
  └─> cli.libsonnet                    # 阶段 2，只依赖 v1
```

| 模块 | 职责 | 允许依赖 |
| --- | --- | --- |
| `generate-params.jsonnet` | 阶段 1 入口：默认静态模板 + 动态 INPUT → v1 | `launch`、默认静态模板 |
| `launch.libsonnet` | 静态模板引擎：函数/对象求值、最小结构校验、`validate` / `generate` | `util` |
| `launch-helpers.libsonnet` | 可选高层辅助：`defaults` / `context` / `params` / 参数分组函数 + 六个自动化模块 | `util`、`parallel`、调用方传入的 profile |
| `parallel.libsonnet` | 纯 TP/PP 推导、约束与 warning、每机 IP | 无阶段 1/2 依赖 |
| `util.libsonnet` | 通用类型判断、默认值读取、错误文本、`featureInput` | 无领域依赖 |
| `templates/profiles/*` | 模型/硬件事实与默认值，纯数据 | 不 import 引擎或辅助模块 |
| `templates/*.libsonnet` | 静态模板，函数或 v1 对象 | 可选 `launch-helpers`、profiles |
| `cli.libsonnet` | 阶段 2 渲染：schema 校验、argv、shell、Docker / Ray / mp | 只依赖 v1 产物 |

## 4. 静态模板契约

一个静态模板必须是以下两种形式之一：

```text
A. function(config={}) -> 静态模板结果对象
B. 静态模板结果对象
```

静态模板结果对象：

```jsonnet
{
  apiVersion: 'vllm-params/v1',   // 必填，精确匹配
  scenario: '<string>',           // 可选，缺省 'custom'
  serve: { ... },                 // 必填，对象
  deployment: { ... },            // 必填，对象
  container: { ... },             // 必填，对象
  extras: { ... },                // 必填，对象
  warnings: [ '<string>' ],       // 可选，缺省 []
  errors: [ '<string>' ],         // 可选，引擎内部使用；generate 剥离
}
```

不变量：

- 高层写法与底层写法产出的对象**形状完全相同**；引擎不区分二者。
- 一份保存下来的 `vllm-params/v1` 产物天然是合法的底层静态模板。
- 引擎只检查 `apiVersion`、四个分区是否为对象、`warnings`/`errors` 是否为数组；完整 v1 schema 与类型校验属于阶段 2。
- `errors` 非空时 `generate` 必须失败，不得输出产物。
- 静态模板结果可以包含额外字段，但 `generate` 只输出 v1 的 7 个顶层键。

## 5. 动态 INPUT 契约

动态 INPUT 是阶段 1 的 `config` 参数：

- 来源：`vllm/params/*.json`，或 `--tla-code config=...` / `--tla-code-file config=...`。
- 形态：扁平部分覆盖对象；未提供的字段由静态模板的默认值补齐。
- 稳定字段名以 README 的“输入参数”表为准；字段名属于用户契约，不得随意重命名。

字段类别：

| 类别 | 字段示例 |
| --- | --- |
| 拓扑与并行 | `nodes`、`totalGpus`、`gpusPerNode`、`parallelMode`、`tensorParallel`、`pipelineParallel`、`distributedBackend` |
| 硬件覆盖 | `gpuMemoryGiB`、`modelLayers`、`dockerShmSize`、`dockerNetworkHost` |
| 网络与端口 | `nodeIpPattern`、`nodeIpStart`、`nodeIps`、`rayPort`、`masterPort` |
| 功能开关 | `speculative`、`thinking`、`reasoningEffort`、`toolCalling`、`multimodal`、`mmEncoderTpMode` |
| 模型/服务/容器覆盖 | `model`、`modelPath`、`modelHostPath`、`image`、`host`、`port`、`apiKey`、`maxModelLen` 等 |
| 逃生舱 | `extraEnv`、`extraMounts`、`extraDockerArgs`、`extraArgs` |
| 场景标签 | `scenario` |

示例：`{"nodes": 2, "totalGpus": 16, "parallelMode": "tp", "distributedBackend": "mp"}`（对应 `multi-h200-2x8-mp-tp16.json` 的核心字段）。

合并语义（高层静态模板）：

- `defaults = mergePatch(profile 默认值, 动态 INPUT)`；
- 字段缺失或为 `null` 时回落到默认值；
- `servedModelName: null` 特例回落到最终的 `model`；
- `totalGpus` 与显式 `gpusPerNode` 的冲突检测只读取**原始动态 INPUT**，不读取默认值；
- 动态 INPUT 是 v1 产物的输入，不是 profile，也不是产物本身。

静态模板类型对动态 INPUT 的处理：

- 底层对象静态模板：忽略动态 INPUT。
- 底层函数静态模板：由函数自行决定是否/如何使用。
- 高层静态模板：通过 `launch-helpers.context` 合并、校验并送入自动化模块。

## 6. `vllm-params/v1` 契约

顶层键固定为：

```text
apiVersion, scenario, serve, deployment, container, extras, warnings
```

### serve

- 键名就是 vLLM 原生参数名（snake_case，对应 `EngineArgs` / `vllm serve`）。
- `model` 是位置参数；其余键出现即表示要传对应旗标。
- 结构化值（`speculative_config`、`default_chat_template_kwargs`）保持对象，不在阶段 1 序列化。
- 布尔旗标只在 `true` 时出现；可选参数未设置时省略。
- `serve` 的已知键集合以阶段 2 渲染器支持的集合为准。新增 vLLM 参数必须同时更新阶段 1 与阶段 2；阶段 2 不会渲染未知键。

### deployment / container / extras

- `deployment`：`nodes`、`gpus_per_node`、`node_ips`、`distributed_executor_backend`，以及按后端条件出现的 `ray_port` / `master_port`。
- `container`：`image`、`environment`、`mounts`、`shm_size`、`network_host`、`name_prefix`。
- `extras`：`serve_args`、`docker_args`，均为字符串数组，阶段 2 原样透传。
- `environment` 的值必须是字符串；`mounts` 每项必须包含 `host_path` / `container_path` / `read_only`。

### 跨字段不变量

以下约束由阶段 1 生成、阶段 2 复核：

- `tensor_parallel_size × pipeline_parallel_size == nodes × gpus_per_node`。
- `language_model_only: true` 与 `mm_encoder_tp_mode` 恰好出现一个。
- `tool_call_parser` 与 `enable_auto_tool_choice: true` 成对出现。
- `distributed_executor_backend: "local"` 只能用于 `nodes = 1`。
- Ray 后端必须带 `ray_port` 且不得带 `master_port`；mp 后端反之。
- `node_ips` 是非空字符串数组，长度等于 `nodes`。

`warnings` 从阶段 1 原样透传到阶段 2 和最终 CLI 产物。

## 7. `vllm-cli/v1` 契约

顶层键固定为：

```text
apiVersion, meta, cli, warnings
```

- `meta.sourceApiVersion` 必须是 `vllm-params/v1`；`meta.scenario` 来自参数产物。
- `cli.serve.argv` 是 exec 形式；`cli.serve.command` 是经过单引号转义的 shell 形式。
- 逐机命令位于 `cli.deployment.nodes[].command`；`docker.argv` 也是 exec 形式。
- 多机模式：Ray 为 `ray-multi-node`，mp 为 `mp-multi-node`，单机为 `single-node`。
- Ray worker 的 `serve` 为 `null`；非 Ray 模式下 `ray` 为 `null`。
- 多机时阶段 2 注入 `VLLM_HOST_IP`；单机不注入。
- 浮点参数用 `%.10g` 渲染，避免 `0.90000000000000002`。
- 渲染结果必须是确定性的；相同 v1 输入产生相同 CLI 输出。

## 8. 静态模板 `ctx` 契约

调用 `launch-helpers.context` 后，静态模板可以依赖以下稳定结构：

```text
ctx.input        # 默认值与动态 INPUT 合并、null 删除回填后的扁平输入
ctx.rawInput     # 保留原始布尔类型的输入，主要供校验
ctx.model        # 调用方传入的模型 profile
ctx.hardware     # 调用方传入的硬件 profile
ctx.launch       # 调用方传入的 launch 策略
ctx.automation   # 六个自动化模块的输出
ctx.errors       # 阶段 1 校验错误
ctx.warnings     # 阶段 1 warning
```

自动化模块的稳定输出：

| 模块 | 输出 |
| --- | --- |
| `worldSize` | `gpusPerNode`, `nodeCount`, `totalGpusErrors`, `conflictErrors` |
| `parallel` | `tensorParallel`, `pipelineParallel`, `expertParallel`, `errors`, `warnings` |
| `network` | `nodeIps`, `errors`, `warnings` |
| `backend` | `backend`, `rayPort`, `masterPort`, `isRay`, `isMp`, `errors` |
| `features` | `chatTemplateKwargs`, `speculative`, `thinking`, `toolCalling`, `multimodal`, `errors` |
| `container` | `environment`, `mounts` |

**单一来源不变量**：

- `worldSize` 是 `totalGpus` / `gpusPerNode` / `nodes` 解析与冲突校验的唯一位置。
- `parallel` 是 TP / PP 推导的唯一位置。
- `network` 是节点 IP 生成的唯一位置。
- `backend` 是后端与条件端口的唯一位置。
- `features` 是功能开关映射到 vLLM 参数的唯一位置。
- `container` 是容器环境变量与挂载归一化的唯一位置。

高层辅助函数（`context` / `defaults` / `params` / `parallelServeParams` / `featuresServeParams` / `inputServeParams` / `backendPortParams`）是可选语法糖；不调用它们不影响引擎工作。

## 9. Profile 契约

高层静态模板通过 profile 提供数据，profile 必须是纯 Jsonnet 数据，不得 import 引擎或辅助模块。

**模型 profile 的必需字段**：

- `id`、`layers`、`weightsGiB`、`vramFloorGiB`、`image`
- `capabilities.tokenizerMode`、`capabilities.supportsMultimodal`
- `capabilities.reasoningParser` / `capabilities.toolParser`（可为 null）
- `runtime.containerNamePrefix`
- `recipe.maxModelLen` / `maxNumBatchedTokens` / `maxCudagraphCaptureSize` / `gpuMemoryUtilization`
- `features.expertParallel`、`features.speculative`、`features.thinking`、`features.reasoningEffort`、`features.toolCalling`、`features.multimodal`、`features.mmEncoderTpMode`
- `features.speculative` 为 true 时，`features.speculativeDefaults.method` 与 `numSpeculativeTokens` 必须合法

**硬件 profile 的必需字段**：

- `gpusPerNode`、`gpuMemoryGiB`、`shmSize`、`networkHost`

**launch 策略的稳定字段**（均可省略，有通用缺省）：

- `host`、`port`、`environment`
- `parallelMode`、`distributedBackend`
- `nodeIpPattern`、`nodeIpStart`、`rayPort`、`masterPort`

低层静态模板不需要任何 profile。

## 10. 回归契约

- `./vllm/run-tests.sh` 必须通过。
- `params-tests` / `cli-tests` / `golden-tests` / `launch-tests` 是行为契约：
  - `params-tests` 冻结阶段 1 的默认值、映射与错误文本；
  - `cli-tests` 冻结阶段 2 的 schema、argv、命令与负例；
  - `golden-tests` 冻结 5 个场景的最终 CLI 投影；
  - `launch-tests` 冻结静态模板、helper 与自动化模块契约。
- 5 个场景的 `vllm-params/v1` 与 CLI 输出必须与基线逐字节一致。只有明确要改变命令行为时，才更新 `tests/golden/legacy-render.json`。
- `jsonnetfmt --test` 与 `bash -n` 必须通过。
