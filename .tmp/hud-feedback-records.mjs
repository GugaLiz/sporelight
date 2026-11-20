import {readFile,writeFile} from 'node:fs/promises';
const report='122-游戏内纸面界面与微光透明合成及全关交互核查.md';
const recordPath='G:/works/liuli/sporelight/docs/69-游戏开发基础质量规则与问题台账.md';
let text=await readFile(recordPath,'utf8');
const additions={
 'GQ-025':'11-18本轮微光破碎/黑圈续修见[122号]('+report+')：核实为共享透明视口二次alpha混合，以及微光/光晕/花草的近共面预深度竞争；预乘混合、独立柔光与1-2原格内错位修复，保留正常深度与真实收集。最终995afa2c/929，三尺寸GPU258项/54原图；15关双视图实看、正式Web及4222的30资源一致。其他人物/美术接受与遮挡开放项不一并关闭。',
 'GQ-030':'11-18追加117号核查见[122号]('+report+')：1-3原路实体可达并通关，补机关上部真实艺术命中，未开放远程旋转；休息后真实方向走开、全15关492状态优先级审计通过。补3-3/3-4根路前端合法导航，477参考意图/21164实体样本全15关完成；游戏内纸面界面/按键与完成态说明更新，最终GPU258项及浏览器1-3真实点击/E种植完成。保留原反馈，未把任意角度始终接岸变成新规则。'
};
for(const [id,extra] of Object.entries(additions)){
 const rows=text.split('\n');
 const index=rows.findIndex(line=>line.startsWith('| '+id+' |'));
 if(index<0)throw Error('Missing issue '+id);
 if(rows[index].includes('[122号]'))throw Error('Already recorded '+id);
 const last=rows[index].lastIndexOf('|');
 rows[index]=rows[index].slice(0,last).trimEnd()+'<br>'+extra+' |';
 text=rows.join('\n');
}
const firstEnd=text.indexOf('\n');
text=text.slice(0,firstEnd+1)+'\n2026-11-18 游戏内UI与117号续反馈：按参考调整纸面关卡/操作卡/底栏与按键说明；GQ-025修透明视口黑圈及微光近共面破碎，GQ-030补机关艺术命中和3-3/3-4根路前端入口，15关实体路线与三尺寸GPU通过，浏览器1-3实际种植完成。版本、边界及交付见[122号]('+report+')；保留未复现项和失败候选。\n'+text.slice(firstEnd+1);
await writeFile(recordPath,text);
