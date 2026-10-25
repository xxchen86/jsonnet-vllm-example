// 新旧等价性测试：jsonnet vllm/golden-tests.jsonnet
//
// 改造前用旧 main.jsonnet 为 5 个场景生成 tests/golden/legacy-render.json。
// 这里对比新两阶段流程的 CLI 投影与旧输出，确保命令文本完全一致。

local cli = import 'lib/cli.libsonnet';
local params = import 'lib/params.libsonnet';
local golden = import 'tests/golden/legacy-render.json';

local scenarios = {
  'multi-h200-2x8-mp-tp16': import 'params/multi-h200-2x8-mp-tp16.json',
  'multi-h200-2x8-ray': import 'params/multi-h200-2x8-ray.json',
  'single-gb200-4gpu': import 'params/single-gb200-4gpu.json',
  'single-h200-8gpu': import 'params/single-h200-8gpu.json',
  'single-h200-8gpu-switches-off': import 'params/single-h200-8gpu-switches-off.json',
};

local names = std.objectFields(scenarios);

local results = {
  [name]:
    local p = params.generate(scenarios[name]);
    local c = cli.render(p);
    local old = golden[name];
    {
      params: p,
      cli: c,
      old: old,
    }
  for name in names
};

{
  [name]: {
    assert results[name].cli.cli.serve == results[name].old.serve : name + ': serve',
    assert results[name].cli.cli.deployment.mode == results[name].old.deployment.mode : name + ': deployment mode',
    assert results[name].cli.cli.deployment.nodes == results[name].old.deployment.nodes : name + ': deployment nodes',
    assert results[name].cli.cli.deployment.commands == results[name].old.deployment.commands : name + ': deployment commands',
    assert results[name].cli.warnings == results[name].old.warnings : name + ': warnings',
    assert results[name].params.scenario == results[name].old.scenario : name + ': scenario',
    assert results[name].params.container.environment == results[name].old.environment : name + ': environment',
    ok: true,
  }
  for name in names
}
