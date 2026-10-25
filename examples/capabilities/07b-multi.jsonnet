// 07b · 多文件输出：-S -m 要求顶层对象的值都是字符串，字段名作为文件名
// -S 让字符串按原始内容写出；-c 会自动创建输出目录
//   jsonnet -S -c -m examples/capabilities/out examples/capabilities/07b-multi.jsonnet

{
  'deployment.json': std.manifestJsonEx({
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: { name: 'demo' },
  }, '  ') + '\n',

  'notes.yaml': std.manifestYamlDoc({
    generatedBy: 'jsonnet',
    note: '多文件输出',
  }),

  'readme.txt': '纯文本值会被原样写入文件。\n',
}
