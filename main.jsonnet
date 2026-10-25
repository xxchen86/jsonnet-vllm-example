// 基础演示：直接运行  jsonnet main.jsonnet
local util = import 'lib/util.libsonnet';

// 1. 本地变量 + 函数
local baseImage = 'demo/api';

// 2. 对象（Jsonnet 的核心），: 是普通字段，:: 是隐藏字段（最终输出不含）
local defaults = {
  name: 'demo-api',
  replicas: 2,
  image: baseImage + ':1.0.0',

  // 隐藏字段：可复用但不会被序列化到输出
  containerPort:: 8080,
};

// 3. 对象继承/覆盖：+ 合并字段，右边优先（浅合并，嵌套对象整体替换）
local prod = defaults {
  replicas: 5,
  image: baseImage + ':1.0.0-prod',
  resources: {
    cpu: '500m',
    memory: '512Mi',
  },
};

// 4. 数组推导 + 标准库
local workers = util.genNames('worker', prod.replicas);

// 5. 最终输出：普通的对象字面量会渲染成 JSON
{
  app: prod {
    // self 只指向「最近的」外层对象，所以先用局部变量抓住它；
    // 否则内层的 labels 里 self 指的是 labels 自己。
    local this = self,
    labels: { app: this.name, tier: 'backend' },
  },
  // 显式读取隐藏字段
  port: prod.containerPort,
  workers: workers,
  // 使用自定义工具库
  workerIndex: util.indexBy([{ name: w, ready: true } for w in workers], 'name'),
  cost: {
    unit: 1.2345,
    rounded: util.roundTo(1.2345, 2),
  },
  // 标准库示例
  summary: {
    workerCount: std.length(workers),
    distinctTiers: std.uniq(std.sort(['backend', 'backend', 'frontend'])),
    checksum: std.md5(prod.name),
  },
}
