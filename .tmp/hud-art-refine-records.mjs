import {readFile,writeFile} from 'node:fs/promises';
const path='G:/works/liuli/sporelight/docs/69-游戏开发基础质量规则与问题台账.md';
const report='124-纸卡装饰原造型重绘与底栏图标续修.md';
let text=await readFile(path,'utf8');
if(text.includes('[124号]'))throw Error('Already recorded');
const rows=text.split('\n');
const index=rows.findIndex(row=>row.startsWith('| GQ-030 |'));
if(index<0)throw Error('Missing GQ-030');
const last=rows[index].lastIndexOf('|');
rows[index]=rows[index].slice(0,last).trimEnd()+'<br>11-19用户否定简化装饰后续修见[124号]('+report+')：参考原纸卡以透明SVG重绘金星与弯曲叶枝，底栏略放大并居中；撤销用回退折箭头、重来用顺时针环形箭头。最终01c951d8/933，三套748项、四尺寸GPU68项/12原图及正式Web实际点击通过，4222的30项资源同源；仅UI范围，不替代其他关卡／音频／性能验收。 |';
text=rows.join('\n');
const first=text.indexOf('\n');
text=text.slice(0,first+1)+'\n2026-11-19 游戏内UI续反馈（GQ-030）：用户否定简化装饰后，参考原纸卡重绘透明星纹与叶饰；底栏略放大并居中，区分撤销／重来图标。源码01c951d8/933，四尺寸GPU、748项定向检查及正式Web实际点击通过，原4222地址与存档保留；见[124号]('+report+')。\n'+text.slice(first+1);
await writeFile(path,text);

