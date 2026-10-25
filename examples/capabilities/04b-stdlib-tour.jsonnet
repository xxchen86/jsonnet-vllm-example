// 04b · 标准库巡礼：函数式、数组、字符串、数学、类型、对象、编码、序列化
// 运行：jsonnet examples/capabilities/04b-stdlib-tour.jsonnet

local users = [
  { name: 'alice', age: 30 },
  { name: 'bob', age: 17 },
  { name: 'carol', age: 42 },
];

{
  // -- 函数式 --------------------------------------------------------------
  functional: {
    mapWithIndex: std.mapWithIndex(function(i, name) '%d:%s' % [i, name], ['a', 'b']),
    mapWithKey: std.mapWithKey(function(k, v) v * 10, { a: 1, b: 2 }),
    filterMap: std.filterMap(function(u) u.age >= 18, function(u) u.name, users),
    flatMap: std.flatMap(function(u) [u.name, u.age], users),
    foldl: std.foldl(function(acc, u) acc + u.age, users, 0),
    all: std.all([true, true]),
    any: std.any([false, true]),
    sum: std.sum([1, 2, 3]),
    avg: std.sum([1, 2, 3]) / std.length([1, 2, 3]),
    minArray: std.foldl(function(acc, x) if x < acc then x else acc, [1, 2], 3),
    maxArray: std.foldl(function(acc, x) if x > acc then x else acc, [1, 2], 3),
  },

  // -- 数组 ----------------------------------------------------------------
  arrays: {
    makeArray: std.makeArray(3, function(i) i * 2),
    range: std.range(1, 5),
    repeat: std.repeat([0], 3),
    slice: std.slice([1, 2, 3, 4, 5], 1, 4, 2),
    reverse: std.reverse([1, 2, 3]),
    join: std.join('-', ['a', 'b']),
    flatten: std.flattenArrays([[1], [2, 3]]),
    find: std.find(2, [1, 2, 2]),
    findSubstr: std.findSubstr('ana', 'banana'),
    contains: std.length(std.find(2, [1, 2])) > 0,
    member: std.member([1, 2], 2),
    count: std.count([1, 1, 2], 1),
    remove: std.filter(function(x) x != 2, [1, 2, 3]),
    removeAt: std.slice([1, 2, 3], 0, 1, 1) + std.slice([1, 2, 3], 2, 3, 1),
    uniqSorted: std.uniq([1, 1, 2, 3]),
  },

  // -- 字符串 --------------------------------------------------------------
  strings: {
    splitLimit: std.splitLimit('a,b,c', ',', 1),
    splitLimitR: std.splitLimitR('a,b,c', ',', 1),
    trim: std.stripChars('  hi  ', ' '),
    stripChars: std.stripChars('--hi--', '-'),
    chars: std.stringChars('abc'),
    substr: std.substr('jsonnet', 0, 4),
    startsWith: std.startsWith('jsonnet', 'json'),
    endsWith: std.endsWith('jsonnet', 'net'),
    replace: std.strReplace('a-b-c', '-', '_'),
    caseInsensitive: std.asciiUpper('JSONNET') == std.asciiUpper('jsonnet'),
    lines: std.lines(['a', 'b']),
    format: std.format('%s=%d', ['x', 1]),
  },

  // -- 数值与数学 ----------------------------------------------------------
  math: {
    abs: std.abs(-3),
    sign: std.sign(-3),
    clamp: std.clamp(5, 1, 3),
    pow: std.pow(2, 10),
    sqrt: std.sqrt(16),
    round: std.round(3.6),
    floor: std.floor(3.6),
    ceil: std.ceil(3.2),
    mod: std.mod(7, 3),
    max: std.max(1, 2),
    min: std.min(1, 2),
    isEven: 4 % 2 == 0,
    isOdd: 3 % 2 == 1,
    isInteger: std.floor(4.0) == 4.0,
    isDecimal: std.floor(4.5) != 4.5,
    pi: std.acos(-1),  // 等价于 std.pi；linter 静态表暂不识别 std.pi
  },

  // -- 类型与相等 ----------------------------------------------------------
  types: {
    type: std.type({}),
    isArray: std.isArray([]),
    isBoolean: std.isBoolean(true),
    isFunction: std.isFunction(function() 1),
    isNull: std.type(null) == 'null',
    isNumber: std.isNumber(1),
    isObject: std.isObject({}),
    isString: std.isString('x'),
    isEmptyString: std.isEmpty(''),
    functionArity: std.length(function(a, b) a + b),
    primitiveEquals: std.primitiveEquals(1, 1),
    assertEqual: std.assertEqual([1, 2], [1, 2]),
  },

  // -- 对象 ----------------------------------------------------------------
  objects: {
    fields: std.objectFields({ a: 1, b:: 2 }),
    fieldsAll: std.objectFieldsAll({ a: 1, b:: 2 }),
    fieldsEx: std.objectFieldsEx({ a: 1, b:: 2 }, true),
    values: std.objectValues({ a: 1 }),
    keysValues: std.objectKeysValues({ a: 1, b: 2 }),
    has: std.objectHas({ a: 1 }, 'a'),
    hasAll: std.objectHasAll({ a: 1, b:: 2 }, 'b'),
    removeKey: local o = { a: 1, b: 2 }; { [k]: o[k] for k in std.objectFields(o) if k != 'a' },
    mergePatch: std.mergePatch({ a: 1, b: { c: 2, d: 3 } }, { b: { c: null, e: 4 } }),
    prune: std.prune({ a: null, b: [], c: {}, keep: 0 }),
    get: std.get({ a: 1 }, 'missing', 42),
  },

  // -- 编码与哈希 ----------------------------------------------------------
  encoding: {
    base64: std.base64('hello'),
    base64Decode: std.base64Decode('aGVsbG8='),
    base64Bytes: std.base64DecodeBytes('aGVsbG8='),
    utf8Encode: std.encodeUTF8('é'),
    utf8Decode: std.decodeUTF8([104, 105]),
    char: std.char(65),
    codepoint: std.codepoint('A'),
    parseInt: std.parseInt('42'),
    parseHex: std.parseHex('ff'),
    parseOctal: std.parseOctal('17'),
    md5: std.md5('jsonnet'),
    // std.sha256 需要 go-jsonnet v0.21+；当前环境 v0.20.0 未提供
    escapeJson: std.escapeStringJson('a"b'),
    escapeBash: std.escapeStringBash("a'b"),
    escapePython: std.escapeStringPython('a"b'),
    escapeDollars: std.escapeStringDollars('$a'),
  },

  // -- 序列化 --------------------------------------------------------------
  serialization: {
    parseJson: std.parseJson('{"a": 1}'),
    parseYaml: std.parseYaml('a: 1\nb: [2, 3]'),
    parseYamlStream: std.parseYaml('---\na: 1\n---\nb: 2\n'),
    json: std.manifestJson({ a: 1 }),
    jsonEx: std.manifestJsonEx({ a: 1 }, '  '),
    jsonMinified: std.manifestJsonMinified({ a: 1 }),
    yamlDoc: std.manifestYamlDoc({ a: 1 }),
    yamlStream: std.manifestYamlStream([{ a: 1 }, { b: 2 }]),
    ini: std.manifestIni({ main: { a: '1' }, sections: { s1: { b: '2' } } }),
    python: std.manifestPython({ a: true }),
    pythonVars: std.manifestPythonVars({ a: 1, b: true }),
    xml: std.manifestXmlJsonml(['a', { href: 'x' }, 'text']),
  },

  // -- 运行环境 ------------------------------------------------------------
  runtime: {
    thisFile: std.thisFile,
    // std.extVar('name') 读取 --ext-str / --ext-code
    // std.native('name') 调用宿主注册的原生函数
    // std.trace('msg', value) 写 stderr 并返回 value
    //
    // 下面这些成员在 v0.22 运行时可用，但 jsonnet-lint 的静态表尚未收录，
    // 直接使用会误报 "Indexed object has no field"，故本文件未调用：
    // std.flattenDeepArray、std.deepJoin、std.equals、std.pi、
    // std.escapeStringXML、std.manifestToml、std.resolvePath
  },
}
