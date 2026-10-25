// 01 · 基础语法：值、表达式、字符串、函数、数组
// 运行：jsonnet examples/capabilities/01-language.jsonnet

local square(x) = x * x;
local factorial(n) = if n <= 1 then 1 else n * factorial(n - 1);
local greet(name, greeting='Hello') =
  '%(greeting)s, %(name)s!' % { greeting: greeting, name: name };

{
  // -- 字面量 --------------------------------------------------------------
  literals: {
    nullValue: null,
    boolean: true,
    integer: 42,
    float: 3.14,
    string: 'text',
    array: [1, 2, 3],
    object: { a: 1 },
  },

  // -- 运算符 --------------------------------------------------------------
  operators: {
    arithmetic: 1 + 2 * 3 - 4 / 2,
    concatenation: 'foo' + '-' + 'bar',
    booleanLogic: 3 > 2 && !(1 == 2) || false,
    membership: std.member(['a', 'b'], 'a'),
    conditional: if 3 % 2 == 0 then 'even' else 'odd',
  },

  // -- 字符串：格式化、文本块 ----------------------------------------------
  strings: {
    positional: '%s-%03d' % ['pod', 7],
    named: greet('Jsonnet'),
    textBlock: |||
      第一行
      第二行：原样保留换行
    |||,
    unicode: '配置也能写中文 🚀',
  },

  // -- 函数：默认参数、命名参数、递归、闭包 --------------------------------
  functions: {
    square: square(9),
    factorial: factorial(5),
    namedArguments: greet(name='World', greeting='Hi'),
    closureResult: (local base = 10; function(x) x + base)(5),
  },

  // -- 数组：切片、拼接、推导 ----------------------------------------------
  arrays: {
    slice: [1, 2, 3, 4, 5][1:4],
    concat: [1, 2] + [3],
    squaresOfOdds: [x * x for x in std.range(1, 6) if x % 2 == 1],
    cartesian: [[x, y] for x in [1, 2] for y in ['a', 'b']],
  },

  // -- 动态字段名 ----------------------------------------------------------
  dynamicField: { ['key_' + std.toString(1 + 1)]: true },
}
