// 单机 8×H200 的硬件容量与容器默认。
// 这是普通 Jsonnet 数据，由静态模板选择性使用。

{
  id: 'h200',
  gpusPerNode: 8,
  gpuMemoryGiB: 141,
  shmSize: '32g',
  networkHost: true,
}
