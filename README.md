# Jsonnet 基础环境（Windows）

## 1. 已安装的运行时

使用官方预编译二进制（go-jsonnet），安装位置：

```
C:\Users\chen xu\AppData\Local\Programs\jsonnet\
├── jsonnet.exe        # 求值器（核心）
├── jsonnetfmt.exe     # 格式化
├── jsonnet-lint.exe   # 静态检查
└── jsonnet-deps.exe   # 依赖图（不执行代码）
```

版本：`v0.22.0`。安装目录已加入**用户级 PATH**，新开的终端直接可用：

```powershell
jsonnet --version
```

> 若当前已打开的终端仍提示找不到命令，重开一个终端即可（PATH 变更不会影响已运行的进程）。

## 2. 目录结构

```
Jsonnet-Test\
├── main.jsonnet              # 主示例：变量、对象继承、隐藏字段、数组推导、std 库
├── lib\util.libsonnet        # 可复用库（import 演示）
└── examples\
    ├── ext-vars.jsonnet      # 外部变量 --ext-str / --ext-code
    ├── yaml-out.jsonnet      # YAML 流式输出
    └── capabilities\         # 按能力拆分的可运行示例集（含独立 README）
        ├── 01-language.jsonnet
        ├── 02-objects.jsonnet
        ├── 03-inheritance.jsonnet
        ├── 04-stdlib.jsonnet
        ├── 04b-stdlib-tour.jsonnet
        ├── 05-modules.jsonnet
        ├── 06-extvar-tla.jsonnet
        ├── 06b-params-file.jsonnet
        ├── 06c-params-tla-file.jsonnet
        ├── 06d-import-params.jsonnet
        ├── 07-output.jsonnet
        ├── 07b-multi.jsonnet
        ├── 08-assertions.jsonnet
        ├── 08b-failing.jsonnet
        ├── 09-k8s.jsonnet
        ├── params\
        │   ├── dev\params.json
        │   └── prod\params.json
        └── lib\
```

## 3. 常用命令

```powershell
# 求值，输出 JSON
jsonnet main.jsonnet

# 注入外部变量（--ext-code 传真正的布尔/数字/数组）
jsonnet examples/ext-vars.jsonnet --ext-str region=cn-north-1 --ext-str tag=v2 --ext-code debug=false

# 输出 YAML（-y 多文档流，-S 单文档字符串）
jsonnet -y examples/yaml-out.jsonnet
jsonnet -S -e "std.manifestYamlDoc({ hello: 'world' })"

# 顶层参数：脚本的最外层是函数时，用 --tla-* 传参
jsonnet -e 'function(k) { got: k }' --tla-str k=v

# 指定 import 搜索路径（默认会搜索脚本所在目录）
jsonnet -J lib main.jsonnet

# 只看依赖，不执行代码（适合 CI 判断哪些文件受影响）
jsonnet-deps main.jsonnet

# 格式化 / 检查
jsonnetfmt --in-place main.jsonnet lib\util.libsonnet
jsonnetfmt --test main.jsonnet            # 仅检查，未格式化时退出码为 2
jsonnet-lint main.jsonnet                 # 未使用变量等 lint
```

## 4. 语言要点速记

| 语法 | 含义 |
| --- | --- |
| `local x = ...;` | 局部变量 / 函数定义，只在当前作用域生效 |
| `:` | 普通字段，会出现在输出中 |
| `::` | 隐藏字段，仅供内部引用 |
| `:::` | 强制可见（覆盖父对象的隐藏字段） |
| `a + b` | 对象合并，右边字段优先（浅合并）；也用于数值/字符串/数组拼接 |
| `a+: b` | 字段级追加：在父对象同名值基础上合并，常用于数组/对象 |
| `std.mergePatch(a, b)` | 递归合并（RFC 7396），`null` 表示删除字段 |
| `self` | 当前对象（注意：内层对象里的 `self` 指它自己） |
| `$` | 当前文件最外层的对象 |
| `super` | 被覆盖的父对象字段，需要显式访问 |
| `{ [k]: v for k in arr }` | 对象推导 |
| `[f(x) for x in arr if cond]` | 数组推导 |
| `import 'a.libsonnet'` | 导入，路径相对于当前文件 |
| `importstr 'x.txt'` | 以字符串形式导入文件内容 |
| `std.extVar('k')` | 读取命令行注入的外部变量 |

`import` 的循环引用是允许的（惰性求值），且同一个文件只会被求值一次。

## 5. 可选补充

- **依赖管理**：`jsonnet-bundler`（`jb init` / `jb install <repo>`），生成 `jsonnetfile.json` 与 `vendor/`。
- **编辑器支持**：VS Code 扩展 `Grafana.vscode-jsonnet`（语法高亮 + 补全 + 格式化）。
- **Python 集成**：`pip install gojsonnet` 后 `import _jsonnet`。

## 6. 能力示例集

`examples\capabilities\` 下按主题拆分了一组可直接运行的示例，完整命令与输出见 [examples/capabilities/README.md](examples/capabilities/README.md)。

| 文件 | 演示的能力 |
| --- | --- |
| `01-language.jsonnet` | 字面量、运算符、字符串格式化 / 文本块、函数默认参数 / 命名参数 / 递归 / 闭包、数组推导、动态字段名 |
| `02-objects.jsonnet` | 普通 / 隐藏 / 强制可见字段、对象 local、`self` / `$`、方法、对象推导、投影、浅合并与 `std.mergePatch` |
| `03-inheritance.jsonnet` | 对象继承、`+:` 追加字段、`super`、`self` 晚绑定、mixin、参数化 mixin、`:::` |
| `04-stdlib.jsonnet` | 推导式、`std.map` / `filter` / `foldl` / `sort`、集合运算、字符串函数、JSON↔YAML、`std.prune` / `get` |
| `04b-stdlib-tour.jsonnet` | 标准库全览：函数式、数组、字符串、数学、类型、对象、编码、序列化 |
| `05-modules.jsonnet` | `import` 参数化库、`importstr` 文本、直接 import JSON |
| `06-extvar-tla.jsonnet` | `std.extVar` + `--ext-str` / `--ext-code`、顶层函数 + `--tla-*` |
| `06b-params-file.jsonnet` | `--ext-code-file` 读取 JSON 文件作为 extVar |
| `06c-params-tla-file.jsonnet` | `--tla-code-file` 读取 JSON 文件作为 TLA |
| `06d-import-params.jsonnet` | 静态 `import` + `-J` 选择参数文件 |
| `07-output.jsonnet` | 默认 JSON、`std.manifestYamlDoc` / `std.manifestJsonEx`、`-S` 字符串输出 |
| `07b-multi.jsonnet` | `-S -m` 多文件输出（字段名→文件名，字符串原样写入） |
| `08-assertions.jsonnet` | 对象断言、顶层断言、`std.assertEqual`、惰性求值、`std.trace` |
| `08b-failing.jsonnet` | 故意失败：断言错误信息与退出码 |
| `09-k8s.jsonnet` | 综合实战：参数化 Deployment、sidecar mixin、多文档 YAML |

> **易错点**：`+` 在嵌套对象上不是递归深合并，右值会整体替换同名子对象；需要递归合并时用 `std.mergePatch`，或在字段上用 `+:`。

## 7. vLLM 实战示例

`vllm/` 下是一个完整的参数模板：用 Jsonnet 承载 DeepSeek-V4.1-Flash 的 vLLM 启动参数，支持按卡数推导 TP / PP、按机器数生成 Ray / mp 多机命令，以及 speculative / thinking / tool calling / multimodal 等开关。完整说明见 [vllm/README.md](vllm/README.md)。

```powershell
# 单机 8×H200
jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/single-h200-8gpu.json

# 2 机 × 8 卡，机内 TP8 + 机间 PP2，Ray 后端
jsonnet vllm/main.jsonnet --tla-code-file config=vllm/params/multi-h200-2x8-ray.json
```
