// 04 · 推导式与标准库（std）
// 运行：jsonnet examples/capabilities/04-stdlib.jsonnet

local users = [
  { name: 'alice', age: 30, roles: ['admin', 'dev'] },
  { name: 'bob', age: 17, roles: ['dev'] },
  { name: 'carol', age: 42, roles: ['ops'] },
];

{
  // -- 推导式 --------------------------------------------------------------
  adults: [u.name for u in users if u.age >= 18],
  byName: { [u.name]: u.age for u in users },
  allRoles: std.set([r for u in users for r in u.roles]),
  indexed: {
    [std.toString(i)]: users[i].name
    for i in std.range(0, std.length(users) - 1)
  },

  // -- 高阶函数 ------------------------------------------------------------
  ages: std.map(function(u) u.age, users),
  adultNames: std.map(function(u) u.name, std.filter(function(u) u.age >= 18, users)),
  totalAge: std.foldl(function(acc, u) acc + u.age, users, 0),
  averageAge: std.foldl(function(acc, u) acc + u.age, users, 0) / std.length(users),
  namesSortedByAge: [u.name for u in std.sort(users, function(u) u.age)],

  // -- 集合运算 ------------------------------------------------------------
  uniqueRoles: std.set([r for u in users for r in u.roles]),
  commonRoles: std.setInter(
    std.set([r for u in users for r in u.roles]),
    std.set(['dev', 'ops', 'qa'])
  ),
  missingRoles: std.setDiff(
    std.set(['dev', 'ops', 'qa']),
    std.set([r for u in users for r in u.roles])
  ),

  // -- 字符串 --------------------------------------------------------------
  strings: {
    upper: std.asciiUpper('jsonnet'),
    replace: std.strReplace('a-b-c', '-', '_'),
    split: std.split('a,b,c', ','),
    join: std.join('|', ['a', 'b', 'c']),
    format: '%s has %d items' % ['cart', 3],
    checksum: std.md5('jsonnet'),
  },

  // -- JSON / YAML 互操作 ---------------------------------------------------
  json: {
    parsed: std.parseJson('{"a": [1, 2], "b": null}'),
    rendered: std.manifestJsonEx({ a: 1, b: [true, false] }, '  '),
    yaml: std.manifestYamlDoc({ a: 1, b: [true, false] }),
  },

  // -- 对象变换 ------------------------------------------------------------
  merged: std.mergePatch(
    { a: 1, b: { c: 2, d: 3 } },
    { b: { c: null, e: 4 } }  // null 表示删除该字段
  ),
  pruned: std.prune({ a: null, b: [], c: {}, d: [null], keep: 0, text: 'ok' }),
  withDefault: std.get({ a: 1 }, 'missing', 42),
  hasField: std.objectHas({ a: 1 }, 'a') && !std.objectHas({ a: 1 }, 'b'),

  // -- 类型与断言 ----------------------------------------------------------
  typeOf: std.type([1, 2]),
  lengths: {
    array: std.length(users),
    string: std.length('jsonnet'),
    object: std.length({ a: 1, b: 2 }),
  },
  assertEqual: std.assertEqual(std.join('-', ['a', 'b']), 'a-b'),
}
