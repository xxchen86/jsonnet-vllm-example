// 并行方案推导：把「机器数 × 每机卡数」翻译成 TP / PP，并做一致性校验。
//
// 约定：
//   - TP × PP 必须等于总卡数（本示例不引入 DP）。
//   - auto：单机把卡全部用于 TP；多机默认「机内 TP、机间 PP」。
//   - tp：所有卡做跨机张量并行。
//   - tp-pp：显式采用「机内 TP、机间 PP」。
// 显式传入 tensorParallel / pipelineParallel 时，会覆盖对应推导值。

local modes = ['auto', 'tp', 'tp-pp'];

{
  modes:: modes,

  plan(config)::
    local nodes = config.nodes;
    local gpusPerNode = config.gpusPerNode;
    local nodesOk =
      std.type(nodes) == 'number' && std.floor(nodes) == nodes && nodes >= 1;
    local gpusOk =
      std.type(gpusPerNode) == 'number' && std.floor(gpusPerNode) == gpusPerNode && gpusPerNode >= 1;
    local worldSize = if nodesOk && gpusOk then nodes * gpusPerNode else 0;

    local autoTp =
      if config.parallelMode == 'tp' then worldSize
      else if gpusOk then gpusPerNode
      else 0;

    local autoPp =
      if config.parallelMode == 'tp' then 1
      else if nodesOk && nodes > 1 then nodes
      else 1;

    local hasTp =
      std.objectHas(config, 'tensorParallel') && config.tensorParallel != null;
    local hasPp =
      std.objectHas(config, 'pipelineParallel') && config.pipelineParallel != null;

    {
      nodes: nodes,
      gpusPerNode: gpusPerNode,
      worldSize: worldSize,
      mode: config.parallelMode,
      tensorParallel: if hasTp then config.tensorParallel else autoTp,
      pipelineParallel: if hasPp then config.pipelineParallel else autoPp,
    },

  validate(config, p)::
    local isIntAtLeast(value, min) =
      std.type(value) == 'number' && std.floor(value) == value && value >= min;

    local numericPlan =
      isIntAtLeast(config.nodes, 1) &&
      isIntAtLeast(config.gpusPerNode, 1) &&
      isIntAtLeast(p.tensorParallel, 1) &&
      isIntAtLeast(p.pipelineParallel, 1);

    local errors =
      (if !isIntAtLeast(config.nodes, 1) then
         ['nodes 必须是 >= 1 的整数（当前：%s，类型：%s）' % [std.toString(config.nodes), std.type(config.nodes)]]
       else []) +
      (if !isIntAtLeast(config.gpusPerNode, 1) then
         ['gpusPerNode 必须是 >= 1 的整数（当前：%s，类型：%s）' % [std.toString(config.gpusPerNode), std.type(config.gpusPerNode)]]
       else []) +
      (if !isIntAtLeast(p.tensorParallel, 1) then
         ['tensorParallel 必须是 >= 1 的整数（当前：%s，类型：%s）' % [std.toString(p.tensorParallel), std.type(p.tensorParallel)]]
       else []) +
      (if !isIntAtLeast(p.pipelineParallel, 1) then
         ['pipelineParallel 必须是 >= 1 的整数（当前：%s，类型：%s）' % [std.toString(p.pipelineParallel), std.type(p.pipelineParallel)]]
       else []) +
      (if std.length(std.find(config.parallelMode, modes)) == 0 then
         ['parallelMode 必须是 %s 之一（当前：%s）' % [std.join('/', modes), config.parallelMode]]
       else []) +
      (if std.type(config.nodeIpPattern) != 'string' then
         ['nodeIpPattern 必须是字符串（当前：%s）' % std.toString(config.nodeIpPattern)]
       else []) +
      (if std.type(config.nodeIpStart) != 'number' then
         ['nodeIpStart 必须是数字（当前：%s）' % std.toString(config.nodeIpStart)]
       else []) +
      (if numericPlan && p.tensorParallel * p.pipelineParallel != p.worldSize then
         ['TP × PP 必须等于总卡数：%d × %d != %d 机 × %d 卡 = %d' % [
           p.tensorParallel,
           p.pipelineParallel,
           config.nodes,
           config.gpusPerNode,
           p.worldSize,
         ]]
       else []);

    local warnings =
      (if std.type(p.pipelineParallel) == 'number' &&
          p.pipelineParallel > 1 &&
          std.type(config.modelLayers) == 'number' &&
          config.modelLayers % p.pipelineParallel != 0 then
         ['模型 %d 层不能被 PP=%d 整除，vLLM 可能拒绝启动；建议改用 parallelMode="tp" 或显式指定 pipelineParallel' % [
           config.modelLayers,
           p.pipelineParallel,
         ]]
       else []) +
      (if std.type(config.nodes) == 'number' &&
          config.nodes > 1 &&
          config.parallelMode == 'tp' then
         ['跨机 TP 对互联带宽敏感，请确认 IB / RoCE 与 NCCL 配置']
       else []) +
      (if std.type(config.nodes) == 'number' &&
          std.type(config.gpusPerNode) == 'number' &&
          std.type(config.gpuMemoryGiB) == 'number' &&
          config.nodes * config.gpusPerNode * config.gpuMemoryGiB < 614 then
         ['总显存约 %d GB，低于官方 614 GB 下限（511 GB 权重 × 1.2）；请确认量化 / 卸载方案' % [
           config.nodes * config.gpusPerNode * config.gpuMemoryGiB,
         ]]
       else []);

    {
      errors: errors,
      warnings: warnings,
    },

  // 生成每台机器的 IP：优先使用显式 nodeIps，否则按 nodeIpPattern 格式化。
  nodeIps(config)::
    local explicit =
      if std.objectHas(config, 'nodeIps') &&
         config.nodeIps != null &&
         std.type(config.nodeIps) == 'array' then config.nodeIps
      else [];
    local nodesOk =
      std.type(config.nodes) == 'number' && std.floor(config.nodes) == config.nodes && config.nodes >= 1;
    local startOk = std.type(config.nodeIpStart) == 'number';
    local patternOk = std.type(config.nodeIpPattern) == 'string';
    if std.length(explicit) > 0 then explicit
    else if nodesOk && startOk && patternOk then [
      std.format(config.nodeIpPattern, [config.nodeIpStart + i])
      for i in std.range(0, config.nodes - 1)
    ] else [],
}
