# Jsonnet 能力示例集

本目录按能力维度拆分了一组可运行示例。以下命令均在**项目根目录**执行（`Jsonnet-Test\`），运行时为 go-jsonnet v0.22.0。

## 能力地图

| 能力 | 关键词 | 示例 |
| --- | --- | --- |
| 基础表达式 | 字面量、运算符、条件、`%` 格式化、`\|\|\|` 文本块 | [01-language.jsonnet](01-language.jsonnet) |
| 函数与计算 | 默认参数、命名参数、递归、闭包、数组推导 | [01-language.jsonnet](01-language.jsonnet) |
| 对象模型 | `:` / `::` / `:::`、`self`、`$`、方法、对象推导、投影 | [02-objects.jsonnet](02-objects.jsonnet) |
| 继承与组合 | 对象 `+`、字段 `+:`、`super`、mixin、晚绑定 | [03-inheritance.jsonnet](03-inheritance.jsonnet) |
| 标准库 | `std.map` / `filter` / `foldl` / `sort`、集合、字符串、JSON/YAML | [04-stdlib.jsonnet](04-stdlib.jsonnet) |
| 标准库进阶 | 函数式、数组、字符串、数学、对象、编码、序列化 | [04b-stdlib-tour.jsonnet](04b-stdlib-tour.jsonnet) |
| 模块化 | `import`、`importstr`、参数化库、导入 JSON | [05-modules.jsonnet](05-modules.jsonnet) |
| 外部参数 | `std.extVar`、`--ext-str` / `--ext-code`、TLA、`--tla-*` | [06-extvar-tla.jsonnet](06-extvar-tla.jsonnet) |
| 文件传参 | `--ext-code-file`、`--tla-code-file`、`import` + `-J` | [06b-params-file.jsonnet](06b-params-file.jsonnet)、[06c-params-tla-file.jsonnet](06c-params-tla-file.jsonnet)、[06d-import-params.jsonnet](06d-import-params.jsonnet) |
| 输出形态 | JSON、YAML、`-S`、`-m` 多文件 | [07-output.jsonnet](07-output.jsonnet)、[07b-multi.jsonnet](07b-multi.jsonnet) |
| 校验与惰性 | 断言、`error`、`std.assertEqual`、惰性求值、`std.trace` | [08-assertions.jsonnet](08-assertions.jsonnet)、[08b-failing.jsonnet](08b-failing.jsonnet) |
| 综合实战 | 参数化 K8s 清单、sidecar mixin、多文档 YAML | [09-k8s.jsonnet](09-k8s.jsonnet) |

---

## 01 · 基础语法

```powershell
jsonnet examples\capabilities\01-language.jsonnet
```

- 8 种基础值：`null`、布尔、数字、字符串、数组、对象等。
- 运算符、条件表达式、`std.member` 成员判断。
- 字符串格式化：`'%s-%03d' % ['pod', 7]`、命名占位符 `'%(name)s' % {...}`。
- `|||` 文本块：保留换行，按闭合分隔符的缩进统一去掉左侧空白。
- 函数：默认参数、命名参数、递归、闭包；数组切片与多层推导。
- 动态字段名：`{ ['key_' + n]: value }`。

## 02 · 对象模型

```powershell
jsonnet examples\capabilities\02-objects.jsonnet
```

- `:` 普通字段、`::` 隐藏字段、`:::` 强制可见字段。
- 对象内 `local`、方法（函数字段）、字段名表达式。
- `self` 指向最近的外层对象；`$` 指向当前文件最外层对象。
- 对象推导、字段投影、`std.objectFields` 与 `std.objectFieldsAll` 的区别。
- 对象 `+` 只在**顶层**合并字段；嵌套同名对象会被整体替换。递归合并用 `std.mergePatch`。

## 03 · 继承与组合

```powershell
jsonnet examples\capabilities\03-inheritance.jsonnet
```

- `base + mixin + { overrides }` 组合配置。
- `ports+: [9100]` 在父值后追加数组；`labels+: {...}` 在父值上合并对象。
- `super.replicas` 读取被覆盖前的值；`self.replicas` 是晚绑定后的最终值。
- 函数返回 mixin：`withResources('500m', '512Mi')`。
- `secret:::` 把父对象的隐藏字段覆盖为可见字段。

> `+` 不是递归深合并。要逐层合并对象，需在每层使用 `+:`，或者用 `std.mergePatch`。

## 04 · 推导式与标准库

```powershell
jsonnet examples\capabilities\04-stdlib.jsonnet
```

- 数组 / 对象推导、多层 `for`、过滤条件。
- `std.map`、`std.filter`、`std.foldl`、`std.sort`。
- 集合运算：`std.set`、`std.setInter`、`std.setDiff`。
- 字符串：`std.asciiUpper`、`std.strReplace`、`std.split`、`std.join`、`std.md5`。
- 数据互操作：`std.parseJson`、`std.manifestJsonEx`、`std.manifestYamlDoc`。
- 对象变换：`std.mergePatch`、`std.prune`、`std.get`、`std.objectHas`。
- 类型与断言：`std.type`、`std.length`、`std.assertEqual`。

标准库完整列表：<https://jsonnet.org/ref/stdlib.html>。

## 04b · 标准库巡礼

```powershell
jsonnet examples\capabilities\04b-stdlib-tour.jsonnet
```

- 函数式：`mapWithIndex`、`mapWithKey`、`filterMap`、`flatMap`、`foldl`、`all`/`any`、`sum`/`avg`/`minArray`/`maxArray`。
- 数组：`makeArray`、`range`、`repeat`、`slice`、`reverse`、`flattenArrays`、`flattenDeepArray`、`deepJoin`、`find`/`findSubstr`、`contains`/`member`/`count`、`remove`/`removeAt`、`uniq`。
- 字符串：`splitLimit`/`splitLimitR`、`trim`、`stripChars`、`stringChars`、`substr`、`startsWith`/`endsWith`、`strReplace`、`equalsIgnoreCase`、`lines`、`format`。
- 数学：`abs`/`sign`/`clamp`、`pow`/`sqrt`、`round`/`floor`/`ceil`、`mod`、`max`/`min`、`isEven`/`isOdd`、`isInteger`/`isDecimal`、`pi`。
- 类型与相等：`type`、`isArray`/`isString`/…、`isEmpty`（字符串）、`length`（函数返回参数个数）、`equals`/`primitiveEquals`/`assertEqual`。
- 对象：`objectFields*`、`objectValues*`、`objectKeysValues*`、`objectHas*`、`objectRemoveKey`、`mergePatch`、`prune`、`get`。
- 编码与哈希：`base64*`、`encodeUTF8`/`decodeUTF8`、`char`/`codepoint`、`parseInt`/`parseHex`/`parseOctal`、`md5`/`sha256`、`escapeString*`。
- 序列化：`parseJson`/`parseYaml`、`manifestJson*`、`manifestYamlDoc`/`manifestYamlStream`、`manifestToml`、`manifestIni`、`manifestPython*`、`manifestXmlJsonml`。
- 运行时：`thisFile`、`resolvePath`、`extVar`、`native`、`trace`。

> v0.22 还提供 `std.deepJoin`、`std.flattenDeepArray`、`std.equals`、`std.pi`、`std.escapeStringXML`、`std.manifestToml`、`std.resolvePath` 等成员；当前 `jsonnet-lint` 的静态表尚未收录它们，直接使用会误报 `Indexed object has no field`，但运行时正常。

## 05 · 模块化

```powershell
jsonnet examples\capabilities\05-modules.jsonnet
```

- `import 'lib/deployment.libsonnet'`：导入一个求值为函数的参数化模板。
- 调用后继续用对象扩展语法覆盖：`deployment('api', 8080) { spec+: { replicas: 3 } }`。
- `importstr 'lib/notes.txt'`：按原始文本读取。
- `import 'lib/data.json'`：JSON 是合法的 Jsonnet，可直接导入。
- import 路径相对于当前文件；同一个文件在一次求值中只计算一次。
- 注意：import 路径必须是字符串字面量，没有运行时动态 import。

## 06 · 外部变量与 TLA

```powershell
# extVar 注入全局值；--ext-code 保留数字/布尔/数组等类型
# TLA 传给顶层函数；忽略 TLA 时使用函数默认值
jsonnet examples\capabilities\06-extvar-tla.jsonnet --ext-str env=prod --ext-code replicas=3 --tla-str app=api --tla-code canary=true

jsonnet examples\capabilities\06-extvar-tla.jsonnet --ext-str env=dev --ext-code replicas=1
```

- `std.extVar('env')` 读取 `--ext-str env=...` 或 `--ext-code env=...`。
- 顶层是函数时，`--tla-str` / `--tla-code` 按参数名传入；函数默认参数仍可生效。
- 缺少必需的 extVar 会直接报错；Jsonnet 没有内置的“带默认值”版本，需自行封装或始终传入。

## 06b–06d · 用 JSON 文件传参

参数很多时，不必堆叠一长串 `--ext-*`，可以直接把一个 JSON 文件作为一个参数对象传入。这是 go-jsonnet CLI 的原生能力。

```powershell
# 1) extVar：整个 JSON 对象注入为 params
jsonnet examples\capabilities\06b-params-file.jsonnet --ext-code-file params=examples\capabilities\params\prod\params.json

# 2) TLA：整个 JSON 对象作为顶层函数参数
jsonnet examples\capabilities\06c-params-tla-file.jsonnet --tla-code-file params=examples\capabilities\params\prod\params.json

# 3) 静态 import + -J 选择配置目录
jsonnet -J examples\capabilities\params\prod examples\capabilities\06d-import-params.jsonnet
```

- `--ext-code-file` / `--tla-code-file` 会把文件内容当作 **Jsonnet 代码**求值；JSON 是合法的 Jsonnet 子集，因此 `.json` 文件可以直接使用。
- 如果参数文件是**不可信的纯数据**，用 `--ext-str-file` 读取字符串，再在源码里 `std.parseJson`，避免执行 Jsonnet 代码：

  ```powershell
  jsonnet -e "std.parseJson(std.extVar('params'))" --ext-str-file params=examples\capabilities\params\prod\params.json
  ```

- `-J` 只是 import 搜索路径；`import 'params.json'` 的路径仍必须是字符串字面量，不能运行时拼接。
- 选择建议：多环境参数推荐 TLA + 文件（依赖显式、易测试）；完全静态配置可用 `import` + `-J`；需要在调用时覆盖个别值则用 extVar/TLA。
- 注意 `06d` 依赖 `-J`，对它做 lint 时也要带路径：
  `jsonnet-lint -J examples\capabilities\params\prod examples\capabilities\06d-import-params.jsonnet`

## 07 · 输出形态

```powershell
# 默认 JSON
jsonnet examples\capabilities\07-output.jsonnet

# 单文档 YAML：顶层字符串用 -S 原样输出
jsonnet -S -e "std.manifestYamlDoc({ hello: 'world' })"

# 多文档 YAML 流：顶层数组 + -y，见 09-k8s.jsonnet
jsonnet -y examples\capabilities\09-k8s.jsonnet

# 多文件输出：顶层对象的每个字段写一个文件；-S 让字符串原样写出，-c 自动建目录
jsonnet -S -c -m examples\capabilities\out examples\capabilities\07b-multi.jsonnet
```

- `std.manifestYamlDoc(obj)` / `std.manifestJsonEx(obj, indent)` 可在配置内部生成字符串。
- `-m` 把顶层对象的每个字段写成一个文件；配合 `-S` 时字符串值按原样写入，否则会按 JSON 编码（带引号/转义）。
- 不加 `-c` 时输出目录必须已存在。
- 多文档 YAML 的完整例子见 [09-k8s.jsonnet](09-k8s.jsonnet)。

## 08 · 断言、错误与惰性

```powershell
jsonnet examples\capabilities\08-assertions.jsonnet

# 故意失败：退出码 1，stderr 包含 "replicas 必须 >= 1"
jsonnet examples\capabilities\08b-failing.jsonnet
```

- 对象断言写在对象字面量里；顶层断言写在最终表达式之前。
- `error 'msg'` 直接中止求值；`std.assertEqual(a, b)` 不相等时抛错。
- Jsonnet 是惰性求值的：隐藏字段 `boom:: error ...` 只要不被访问就不会触发。
- `std.trace(msg, value)` 把调试信息写到 stderr，并原样返回 `value`。
- 没有 `try/catch`；第一个错误会中止整个求值。

## 09 · 综合实战：Kubernetes 清单

```powershell
# JSON
jsonnet examples\capabilities\09-k8s.jsonnet

# 多文档 YAML（顶层数组）
jsonnet -y examples\capabilities\09-k8s.jsonnet
```

- 用 `env`、`app`、`imageTag` 参数化镜像、副本数、日志级别。
- 用 `withSidecar(...)` mixin 通过 `containers+:` 追加 sidecar。
- 顶层数组配合 `-y` 直接得到多文档清单，可接 `kubectl apply -f -`。

---

## 标准库的纯度与副作用

绝大多数 `std` 函数是纯函数：相同输入得到相同输出，不修改状态，也不读写文件或网络。例外与边界如下：

| 成员 | 性质 |
| --- | --- |
| `std.trace(msg, value)` | 有意产生副作用：向 stderr 打印 `msg`，并返回 `value`。触发时机受惰性求值影响，不要依赖打印次数。 |
| `std.native(name)` | 调用宿主注册的原生函数；是否纯、是否有副作用由宿主决定；未注册时返回 `null`。 |
| `std.extVar(name)` | 读取 VM 的外部变量。同一次求值内稳定，但结果取决于启动参数，不是仅由源码和显式参数决定；缺少变量会报错。 |
| `std.thisFile` | 当前文件路径，属于求值上下文；同一文件内是常量，不产生副作用。 |
| `std.resolvePath(path, base)` | 纯字符串路径运算，不访问文件系统；Windows 下注意使用 `/`。 |

断言失败、`error`、非法解析输入等会中止整个求值：这不是副作用，而是“部分函数”的失败，且 Jsonnet 没有 `try/catch`。

惰性求值意味着未被使用的表达式不会求值，副作用也不会发生。当前 go-jsonnet 实现会缓存已求值的 thunk（例如同一个 `local` 或对象字段里的 `std.trace` 只打印一次），但不应把 trace 的次数当作语言保证。

---

## 能力边界（它不做什么）

| 限制 | 说明 |
| --- | --- |
| 无通用 I/O | 不能读写任意文件、访问网络或环境变量；外部输入走 extVar / TLA，文件内容走 `import` / `importstr` / `importbin`。 |
| 无动态 import | import 路径必须是字符串字面量。 |
| 无 try/catch | 错误会中止求值；用断言尽早给出可读信息。 |
| 无命令式循环 | 用推导式、递归和标准库替代。 |
| 输出必须可序列化 | 函数不能直接出现在输出中；可放进隐藏字段或先调用。 |
| 对象键必须是字符串 | 数字键需 `std.toString(i)`。 |
| `+` 不是深合并 | 嵌套对象会整体替换；用 `+:` 或 `std.mergePatch`。 |

## 质量工具

```powershell
jsonnetfmt --in-place examples\capabilities\01-language.jsonnet
jsonnetfmt --test examples\capabilities\01-language.jsonnet
jsonnet-lint examples\capabilities\01-language.jsonnet
jsonnet-deps examples\capabilities\05-modules.jsonnet
```
