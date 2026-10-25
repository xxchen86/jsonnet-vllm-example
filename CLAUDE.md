# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库定位

这是一个以 vLLM 参数工作流为核心的 Jsonnet demo/教学/原型验证仓库，不是生产级部署工具。核心用于验证 DeepSeek-V4.1-Flash 的 vLLM 启动参数「两阶段」工作流：

- `vllm/`：仓库核心，把 DeepSeek-V4.1-Flash 的 vLLM 部署参数拆成「参数生成 → CLI 渲染」两阶段；字段、产物 schema 与部署说明见 `vllm/README.md`，架构见 `vllm/ARCHITECTURE.md`。
- `examples/`：收束全部 Jsonnet 语言教学示例（标准库、模块、TLA、输出格式、K8s 清单等）；`examples/README.md` 是完整教程，`examples/capabilities/README.md` 是按能力拆分的示例集。根 `README.md` 是 vLLM 核心入口。

运行时为 go-jsonnet v0.20.0（`jsonnet` / `jsonnetfmt`），没有构建步骤，也没有包管理器。测试脚本额外依赖 `python3`（仅用于 `json.tool` 校验产物可解析）。

## 工作深度（demo 级）

本项目只要求 demo 级正确性：

- 两阶段端到端能跑通；
- `cli` 输出与 `vllm/tests/golden/legacy-render.json` 的命令等价；
- README、命令、路径不失效；
- 修复明显会破坏 demo 的 bug。

不要做生产级工作：安全加固、schema 模糊测试/穷举边界、性能、可移植性、容灾/重试、完整 CI、生产级错误处理或大规模重构。不要为“更完善”引入新依赖、抽象层、配置项或测试框架；优先最小、可读的 Jsonnet 和 Linux shell。

验证以 `./vllm/run-tests.sh`、`jsonnetfmt --test`、`bash -n` 为准；不要随意扩大测试范围，或做跨大量配置的等价性 sweep。不影响 demo 跑通或文档可用的问题记录为 nit，不阻塞提交。

## 常用命令

```bash
# 全量测试：四层断言 + 5 个场景的两阶段渲染 + 负例
./vllm/run-tests.sh

# 单层测试（断言失败时 jsonnet 以非 0 退出）
jsonnet vllm/params-tests.jsonnet
jsonnet vllm/cli-tests.jsonnet
jsonnet vllm/golden-tests.jsonnet
jsonnet vllm/launch-tests.jsonnet

# 单个场景：阶段 1 -> 阶段 2
./vllm/render-params.sh -c vllm/params/single-h200-8gpu.json -o vllm/out/x.params.json
./vllm/render-cli.sh -p vllm/out/x.params.json -o vllm/out/x.cli.json

# 入口是顶层函数，用 TLA 传参；config 缺省为 {}，template 缺省为默认静态模板
jsonnet vllm/generate-params.jsonnet --tla-code 'config={nodes:2, gpusPerNode:8, parallelMode:"tp"}'
jsonnet vllm/generate-params.jsonnet --tla-code-file template=vllm/out/x.params.json
jsonnet vllm/render-cli.jsonnet --tla-code-file params=vllm/out/x.params.json

# 格式化检查 / 自动修复（未格式化时 --test 退出码为 2）
jsonnetfmt --test vllm/*.jsonnet vllm/lib/*.libsonnet vllm/templates/*.libsonnet vllm/templates/profiles/*/*.libsonnet
jsonnetfmt --in-place vllm/lib/launch-helpers.libsonnet

# shell 语法检查
bash -n vllm/render-params.sh vllm/render-cli.sh vllm/run-tests.sh

# Jsonnet 语言示例（全部在 examples/ 下）
jsonnet examples/main.jsonnet
jsonnet examples/capabilities/09-k8s.jsonnet
```

测试没有按用例选择器：每个 `*-tests.jsonnet` 是一个完整断言程序，修改断言后重跑整个文件。`run-tests.sh` 会遍历 `vllm/params/*.json`，新增场景只需放入该目录。

## 两阶段架构

```text
vllm/params/*.json               动态 INPUT（机器数、卡数、功能开关）
        │  generate-params.jsonnet  (TLA: config / template)
        ▼
vllm/templates/*.libsonnet       静态模板（函数或 vllm-params/v1 对象）
        │  ├─ lib/launch.libsonnet           引擎：求值 / 校验 / 投影
        │  └─ lib/launch-helpers.libsonnet   可选高层：defaults / context / 自动化模块
        │           └─ lib/parallel.libsonnet TP/PP 推导
        ▼
vllm-params/v1 产物              serve / deployment / container / extras
        │  render-cli.jsonnet       (TLA: params)
        ▼
vllm/lib/cli.libsonnet           独立 schema 校验 / argv / shell / Docker / Ray / mp
        ▼
vllm-cli/v1 产物                 cli.serve + cli.deployment.nodes[] + warnings
```

关键约束：

- **阶段解耦**：`cli.libsonnet` 不 import `launch.libsonnet` / `launch-helpers.libsonnet` / `parallel.libsonnet` / 静态模板，只消费 `vllm-params/v1`，缺失必填字段或类型不符时直接报错。阶段 2 因此也能渲染外部保存的参数产物；同时阶段 1 会识别并拒绝把参数产物误当 config 传入。
- **静态模板两种写法**：模板可以是 `function(config={})` 或 `vllm-params/v1` 对象；高层调用 `launch-helpers.libsonnet`（profile + `ctx.automation.*`），底层直接写 v1 字面量。引擎不区分二者，产物 schema 一致。
- **产物即 vLLM 参数**：`serve` 的键就是 vLLM `EngineArgs` / `vllm serve` 的 snake_case 参数名。键出现即表示要传对应 flag；例外是 `model` 作为位置参数、`pipeline_parallel_size: 1` 渲染时省略、单机 `distributed_executor_backend: "local"` 不传 flag。
- **可选字段**：布尔 flag 只在 `true` 时出现；`api_key`、`max_num_seqs`、`enforce_eager` 等未设置时整个键省略。`speculative_config` / `default_chat_template_kwargs` 在阶段 1 保持结构化对象，阶段 2 才用 `std.manifestJsonMinified` 序列化。
- **校验分层**：`launch.analyze` 返回 `{errors, warnings, ...}`；`launch.validate` 只返回 errors/warnings；`launch.generate` 用 assert 拦截 errors 并投影 7 个顶层键。`cli.validate` / `cli.render` 同理。新增字段时需要同时更新 `launch-helpers.libsonnet` 的映射和 `cli.libsonnet` 的 schema。
- **并行推导**（`parallel.libsonnet`）：`auto` 单机为 TP=每机卡数、PP=1，多机为 TP=每机卡数、PP=机器数；`tp` 为跨机 TP=总卡数、PP=1；`tp-pp` 为机内 TP、机间 PP。显式 `tensorParallel` / `pipelineParallel` 覆盖推导值，但仍必须满足 `TP × PP = nodes × gpusPerNode`。单机后端强制为 `local`。
- **多机渲染**：Ray 模式 head 节点先 `ray start --head` 再 `vllm serve`，worker 只执行 `ray start`（`serve: null`），且不得传 `--nnodes`；mp 模式使用 `--nnodes/--node-rank/--master-addr/--master-port`，worker 额外加 `--headless`。Docker 命令把内部命令包进 `--entrypoint bash -c`。
- **命令转义**：`cli.libsonnet` 的 `shellQuote` 对安全字符原样输出，否则做单引号转义；浮点用 `%.10g` 格式化，避免 Jsonnet 输出 `0.90000000000000002`。

## 测试与基线

- `params-tests.jsonnet`：阶段 1 断言（schema、TP/PP、功能开关、环境变量/挂载归一化、警告、6 个负例）。
- `cli-tests.jsonnet`：阶段 2 断言（argv 顺序/flag、Ray/mp/Docker、端口映射、逃生舱、8 个 schema 负例）。
- `golden-tests.jsonnet`：把 5 个场景的新两阶段输出与 `tests/golden/legacy-render.json` 逐项对比。该 fixture 是重构前旧 `vllm/main.jsonnet` 冻结的命令文本；**只有确认要改变对外命令行为时才更新它**。
- `launch-tests.jsonnet`：静态模板引擎、六个自动化模块、helper 与内联写法等价、自定义 profile 与负例。
- `run-tests.sh` 末尾的负例保证：参数产物不能当 config 传给阶段 1、错误 `apiVersion` 会被阶段 2 拒绝、非法 TP/PP 会被拒绝。

## 产物与文件约定

- `vllm/out/`、`examples/capabilities/out*/` 是生成目录，已在 `.gitignore` 中忽略；`run-tests.sh` 写入 `vllm/out/tests/`。
- 设置 `apiKey` 会把密钥明文写入参数产物，不要把带密钥的产物提交。
- 渲染脚本会 `cd` 到仓库根目录，`-c` / `-p` / `-o` 路径都按仓库根目录解析。
- 新增功能开关时，同步更新 `launch-helpers.libsonnet` 的 defaults / context / 模块映射，`cli.libsonnet` 的 schema / 渲染，以及对应测试；行为变化还要更新对应的 `README.md`。

## Jsonnet v0.20.0 注意事项

- `jsonnet-lint` / `jsonnet-deps` 不在 apt 包中；`examples/capabilities/04b-stdlib-tour.jsonnet` 对较新的 std 成员用等价写法演示。
- `+` 是浅合并，深层合并用 `+:` 或 `std.mergePatch`；`std.mergePatch` 中 `null` 表示删除字段。参数默认值逻辑依赖这一点（配合 `getOr` 回落），因此输入冲突检测（如 `totalGpus` 与显式 `gpusPerNode`）读取的是原始 `config`，而不是合并后的对象。
