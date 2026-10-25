// 静态模板引擎：函数或 vllm-params/v1 对象 -> 标准 v1 产物。
//
// 静态模板可以是：
//   - function(config={}) -> 静态模板结果对象
//   - 静态模板结果对象（通常是 vllm-params/v1 产物）
//
// 静态模板结果对象：
//   { apiVersion, scenario?, serve, deployment, container, extras, warnings?, errors? }
// errors/warnings 缺省为 []；generate 会剥离 errors。
//
// 引擎只做最小结构校验；完整 v1 schema/类型校验由阶段 2 cli.validate 负责。

local util = import 'util.libsonnet';

local apiVersion = 'vllm-params/v1';
local partitions = ['serve', 'deployment', 'container', 'extras'];

{
  apiVersion:: apiVersion,

  evaluate(declaration, config)::
    if std.type(declaration) == 'function' then
      { result: declaration(config), errors: [] }
    else if std.type(declaration) == 'object' then
      { result: declaration, errors: [] }
    else
      {
        result: {},
        errors: ['template 必须是函数或 vllm-params/v1 对象（当前类型：%s）' % std.type(declaration)],
      },

  analyze(declaration, config)::
    local e = $.evaluate(declaration, config);
    local r = e.result;
    local isObj = util.isObj(r);
    local structuralErrors =
      e.errors +
      (if !isObj then ['template 求值结果必须是对象'] else []) +
      (if isObj && !(std.objectHas(r, 'apiVersion') && r.apiVersion == apiVersion) then
         ['template 结果 apiVersion 必须是 %s' % apiVersion]
       else []) +
      (if isObj then
         std.flattenArrays([
           (if std.objectHas(r, k) && util.isObj(r[k]) then
              []
            else
              ['template 结果缺少对象分区 %s' % k])
           for k in partitions
         ])
       else []) +
      (if isObj && std.objectHas(r, 'warnings') && !util.isArr(r.warnings) then
         ['template 结果 warnings 必须是数组']
       else []) +
      (if isObj && std.objectHas(r, 'errors') && !util.isArr(r.errors) then
         ['template 结果 errors 必须是数组']
       else []);

    local declErrors =
      if isObj && std.objectHas(r, 'errors') && util.isArr(r.errors) then r.errors else [];
    local warnings =
      if isObj && std.objectHas(r, 'warnings') && util.isArr(r.warnings) then r.warnings else [];

    {
      errors: structuralErrors + declErrors,
      warnings: warnings,
      scenario: if isObj then util.getOr(r, 'scenario', 'custom') else 'custom',
      serve: if isObj then util.getOr(r, 'serve', {}) else {},
      deployment: if isObj then util.getOr(r, 'deployment', {}) else {},
      container: if isObj then util.getOr(r, 'container', {}) else {},
      extras: if isObj then util.getOr(r, 'extras', {}) else {},
    },

  validate(declaration, config)::
    local a = $.analyze(declaration, config);
    { errors: a.errors, warnings: a.warnings },

  generate(declaration, config)::
    local a = $.analyze(declaration, config);
    {
      assert std.length(a.errors) == 0 : std.join('; ', a.errors),

      apiVersion: apiVersion,
      scenario: a.scenario,
      serve: a.serve,
      deployment: a.deployment,
      container: a.container,
      extras: a.extras,
      warnings: a.warnings,
    },
}
