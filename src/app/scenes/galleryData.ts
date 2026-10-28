import {LEVELS,totalSpores,CHAPTERS} from '../game/levels';
import type {SaveData,AppState} from '../types';
export const GALLERY_CATEGORIES=['全部','植物','生物','建筑','奇物'] as const;
export type GalleryCategory=typeof GALLERY_CATEGORIES[number];
export type GalleryMode='entry'|'story';
export interface GalleryItem {
 id:string;title:string;desc:string;image:string;habitat:string;firstFound:string;category:Exclude<GalleryCategory,'全部'>;story:string[];poem:string;
}
export const GALLERY_ITEMS:ReadonlyArray<GalleryItem>=[
 {id:'flowerbud',title:'萌芽花台',desc:'在古老的土地上，沉睡的种子悄然萌发。柔嫩的花瓣承接着第一缕微光，治愈着每一寸疲惫的心灵。',image:'./images/production/bloom.png',habitat:'苔藓湿地、遗迹花园',firstFound:'苔藓山谷',category:'植物',story:['雨停之后，旧石阶上只剩一小块干涸的土地。{name}在这里停下，把一粒孢子轻轻放进裂缝。','花朵没有立刻回答。直到第一缕阳光穿过遗迹，它才展开花瓣，替小小的旅人接住了前方的路。'],poem:'一朵花开的地方，也可以是一段归途。'},
 {id:'moss',title:'发光苔藓',desc:'把白天的温暖藏进柔软的叶片，在夜里替旅人点亮脚边。越是安静的地方，越能看见它的光。',image:'./images/production/light.png',habitat:'潮湿岩壁、洞穴石阶',firstFound:'雨滴池塘',category:'植物',story:['大家都抬头寻找星星时，苔藓却低着头，把微光留给脚下。它知道，有些路只能一步一步地照亮。','{name}点亮第一片苔藓后，黑暗里浮现出一条从未被看见的小径。原来希望也可以长得这样低、这样近。'],poem:'小小的光，也能照见下一步。'},
 {id:'vine',title:'藤蔓桥',desc:'从一粒孢子舒展开的绿色桥梁，让彼此遥望的石台重新相连。它记得每一次温柔的回头。',image:'./images/gallery-journal/vine.png',habitat:'苔藓峡谷、断裂的石台',firstFound:'苔藓山谷',category:'奇物',story:['两座石台已经遥望彼此很久。风能越过它们之间的空隙，种子却总是落不到对岸。','后来，{name}带来了一粒愿意伸展的孢子。藤蔓用一整个清晨慢慢生长，终于把等待变成了一座桥。'],poem:'有些连接，来自一次小小的伸手。'},
 {id:'bug',title:'发光小虫',desc:'喜欢温暖的花香，愿意跟随相邻的微光。别催促它，它会用自己的步调慢慢找到家。',image:'./images/production/bug.png',habitat:'花香小径、池塘芦苇边',firstFound:'苔藓山谷',category:'生物',story:['这只小虫记得家的气味，却忘记了回去的方向。每当风吹动花铃，它都会抬起头，试着分辨熟悉的声音。','{name}没有替它赶路，只是一站一站地摇响花铃。走到最后一朵花旁，小虫终于亮起了比星星还柔软的光。'],poem:'陪伴，就是愿意等一等。'},
 {id:'lilypad',title:'睡莲',desc:'安静漂浮在水面，等一滴雨唤醒花心。舒展的叶片会轻轻托起旅人，把勇气送往彼岸。',image:'./images/production/lily-open.png',habitat:'雨滴池塘、静水浅滩',firstFound:'雨滴池塘',category:'植物',story:['睡莲总说自己并不擅长远行。它只是在原地听雨，看水纹一次次走向远方。','直到{name}站上它的叶片，睡莲才发现：留在原地的生命，也可以把别人的旅程轻轻托起。'],poem:'轻轻一跃，便是新的风景。'},
 {id:'mushroom',title:'光菇',desc:'洞穴里不需要火的小灯。菌盖下藏着一圈暖金色的光，让安静的夜晚也有家的温度。',image:'./images/gallery-journal/mushroom.png',habitat:'星光洞穴、湿润的树根下',firstFound:'星光洞穴',category:'植物',story:['洞穴深处，光菇从不问旅人为什么来到这里。它只是亮着，像一扇愿意一直等人归来的窗。','{name}在菌盖旁歇了一会儿。远处的水声变得很轻，连那些还没说出口的担心，也慢慢安静下来。'],poem:'总有一盏灯，愿意为你留着。'},
 {id:'arch',title:'遗迹拱门',desc:'旧石头记得很久以前的回声。苔藓和小花沿着裂缝生长，让经过这里的脚步都有了温柔的回响。',image:'./images/production/arch.png',habitat:'古苔原遗迹、山谷石阶',firstFound:'苔藓山谷',category:'建筑',story:['没有人记得这座拱门通向过哪里。它只留下半圈天空，和被风吹得很慢的旧名字。','当{name}穿过门下，新生的藤蔓轻轻摇了一下。也许石头并不需要恢复从前，它只想继续迎接新的相遇。'],poem:'时间留下的空隙，后来长满了花。'},
 {id:'starflower',title:'星花',desc:'只在被温柔照亮的夜里开放。花瓣记得叶、雨、星与月的次序，也记得每一粒被找回的微光。',image:'./images/reference-scenes/plant-cave-bloom.png',habitat:'星光洞穴最深处',firstFound:'星光洞穴',category:'植物',story:['人们说，星花睡着的时候，会梦见整片苔原。山谷里的花香、池塘的雨声，都安静地停在它的花瓣上。','{name}找回八粒孢子，循着星图点亮最后一束光。花开时，曾经被帮助过的生命都在微光里回应：你走过的地方，已经有了家的模样。'],poem:'你也是这片星光的一部分。'},
];
export const relatedGalleryLevels=(item:GalleryItem)=>LEVELS.filter(l=>l.rewards.includes(item.id));
export const galleryUnlocked=(save:SaveData,item:GalleryItem)=>!!save.gallery[item.id]||relatedGalleryLevels(item).some(l=>save.levels[l.id]?.completed);
export function galleryMarks(save:SaveData,item:GalleryItem){
 if(!galleryUnlocked(save,item))return 0;
 const completion=Math.max(0,...relatedGalleryLevels(item).filter(l=>save.levels[l.id]?.completed).map(l=>Math.min(1,(save.levels[l.id].bestCollected||0)/Math.max(1,totalSpores(l)))));
 return 1+Math.floor(completion*4);
}
export function galleryFirstFound(save:SaveData,item:GalleryItem){
 const level=relatedGalleryLevels(item).find(l=>save.levels[l.id]?.completed);
 if(!level)return '记于微光旅程';
 return `${CHAPTERS.find(c=>c.id===level.chapter)!.title} ${level.id} · ${level.title}`;
}
export function galleryHint(item:GalleryItem){const first=relatedGalleryLevels(item)[0];return first?`在 ${first.id} · ${first.title} 完成一次新的相遇。`:'继续探索微光苔原。';}
export function gallerySelection(state:AppState){
 const category=GALLERY_CATEGORIES.includes(state.galleryCategory as GalleryCategory)?state.galleryCategory!:'全部';
 const items=GALLERY_ITEMS.filter(i=>category==='全部'||i.category===category);
 const selected=items.find(i=>i.id===state.gallerySelected)??items.find(i=>galleryUnlocked(state.save,i))??items[0]??null;
 const mode:GalleryMode=state.galleryMode==='story'?'story':'entry';
 return {category,items,selected,mode};
}
