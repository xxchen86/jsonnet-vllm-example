# DeepSeek-V4.1-Flash × vLLM（Jsonnet 两阶段参数生成）

本仓库的核心是 [`vllm/`](vllm/README.md)：用 Jsonnet 把 DeepSeek-V4.1-Flash 的 vLLM 启动参数拆成两阶段，从动态 INPUT 生成参数产物，再渲染成可直接执行的 CLI / Docker / Ray / mp 命令。

```text
动态 INPUT ──────────────┐
                         ├─> 静态模板求值 ─> vllm-params/v1 ─> vllm-cli/v1
静态模板（templates/*）──┘
        阶段 1                                    阶段 2
```

- **阶段 1（参数生成）**：静态模板 + 动态 INPUT（机器数、卡数、功能开关）→ vLLM 原生参数产物 `vllm-params/v1`。
- **阶段 2（CLI 渲染）**：参数产物 → `argv`、shell 命令、逐机命令（Docker / Ray / mp）`vllm-cli/v1`。阶段 2 独立校验 schema，不依赖阶段 1 的任何模块。

> 这是 demo / 原型验证仓库，不是生产级部署工具；目标镜像 `vllm/vllm-openai:deepseekv41-flash-0909`（vLLM >= 0.31.0）。

## 目录结构

```text
jsonnet-vllm-example/
├── vllm/                 # 仓库核心：两阶段参数生成与 CLI 渲染
│   ├── README.md         # 字段、产物 schema、部署说明
│   ├── ARCHITECTURE.md   # 核心架构与模块契约
│   ├── generate-params.jsonnet / render-cli.jsonnet
│   ├── lib/ templates/ params/ tests/
│   └── render-params.sh / render-cli.sh / run-tests.sh
└── examples/             # Jsonnet 语言教学示例（非核心）
    ├── README.md         # 语言教程与命令速查
    ├── main.jsonnet
    ├── ext-vars.jsonnet / yaml-out.jsonnet
    ├── lib/
    └── capabilities/     # 按能力拆分的可运行示例集
```

## 快速开始

依赖 go-jsonnet v0.20.0（`jsonnet` / `jsonnetfmt`），测试脚本额外需要 `python3`。

```bash
# 阶段 1：生成参数产物
./vllm/render-params.sh \
  -c vllm/params/single-h200-8gpu.json \
  -o vllm/out/single-h200-8gpu.params.json

# 阶段 2：渲染 CLI
./vllm/render-cli.sh \
  -p vllm/out/single-h200-8gpu.params.json \
  -o vllm/out/single-h200-8gpu.cli.json
```

也可以直接调用入口（TLA 传参，省略 `template` 时使用默认静态模板）：

```bash
mkdir -p vllm/out

jsonnet vllm/generate-params.jsonnet \
  --tla-code-file config=vllm/params/single-h200-8gpu.json \
  > vllm/out/single-h200-8gpu.params.json

jsonnet vllm/render-cli.jsonnet \
  --tla-code-file params=vllm/out/single-h200-8gpu.params.json \
  > vllm/out/single-h200-8gpu.cli.json
```

示例 INPUT 覆盖单机 H200 / GB200、2 机 Ray（TP8 × PP2）与 2 机 mp（TP16）；完整列表见 [vllm/README.md](vllm/README.md#示例参数文件)。

## 测试

```bash
# 四层断言 + 5 个场景的两阶段渲染 + 负例
./vllm/run-tests.sh

# 格式化检查与 shell 语法检查
jsonnetfmt --test vllm/*.jsonnet vllm/lib/*.libsonnet vllm/templates/*.libsonnet \
  vllm/templates/profiles/*/*.libsonnet
bash -n vllm/render-params.sh vllm/render-cli.sh vllm/run-tests.sh
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [vllm/README.md](vllm/README.md) | 核心文档：输入字段、两阶段产物 schema、多机部署、功能开关、测试 |
| [vllm/ARCHITECTURE.md](vllm/ARCHITECTURE.md) | 核心架构、阶段边界与模块契约 |
| [examples/README.md](examples/README.md) | Jsonnet 语言教程：环境、语法速记、常用命令 |
| [examples/capabilities/README.md](examples/capabilities/README.md) | 按能力拆分的 Jsonnet 可运行示例 |
| [CLAUDE.md](CLAUDE.md) | 仓库协作约定与验证方式 |
