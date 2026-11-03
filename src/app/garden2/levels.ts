import {cell,modCell,type GardenLevel,type Tile,type Landmark,type Module,type Root} from './types';
const rect=(x:number,z:number,w:number,d:number,h=0,small=false):Tile[]=>Array.from({length:w*d},(_,i)=>({id:cell(x+i%w,z+Math.floor(i/w)),x:x+i%w,z:z+Math.floor(i/w),h,small}));
const path=(points:[number,number][],h=0,small=false):Tile[]=>{const out:Tile[]=[];for(let i=0;i<points.length-1;i++){let [x,z]=points[i];const [ex,ez]=points[i+1];out.push(...rect(x,z,1,1,h,small));while(x!==ex||z!==ez){if(x!==ex)x+=Math.sign(ex-x);else z+=Math.sign(ez-z);out.push(...rect(x,z,1,1,h,small));}}return out;};
const mark=(id:string,x:number,z:number,label:string,kind:Landmark['kind'],text?:string):Landmark=>({id,tile:cell(x,z),label,kind,text});
const moduleMark=(id:string,m:string,label:string,kind:Landmark['kind'],x=0,z=0):Landmark=>({id,tile:modCell(m,x,z),label,kind});
const elbow:[number,number][]=[[0,0],[-1,0],[-2,0],[0,1],[0,2]];
const deck:[number,number][]=[[-1,-1],[0,-1],[1,-1],[-1,0],[0,0],[1,0],[-1,1],[0,1],[1,1]];
const lift=(id:string,x:number,z:number,high=2):Module=>({id,x,z,h:0,shape:deck,kind:'lift',low:0,high});
function level(id:string,title:string,chapter:GardenLevel['chapter'],rule:string,intro:string,total:number,tiles:Tile[],marks:Landmark[],modules:Module[]=[],roots:Root[]=[],start=cell(0,0),dual=false):GardenLevel{
 const unique=[...new Map(tiles.map(t=>[t.id,t])).values()];
 const base=marks.filter(m=>!['core','turn','valve','lever','plate','latch','slot','song'].includes(m.kind));
 const places=[...base.map(m=>m.tile),...unique.filter((_,i)=>i%3===0).map(t=>t.id)];
 const spores=[...new Set(places)].filter(t=>t!==start).slice(0,total);
 return {id,title,chapter,rule,intro,total,tiles:unique,marks,modules,roots,start,dual,collectibles:spores.map((tile,i)=>({id:`spore-${i}`,tile})),story:''};
}
const out:GardenLevel[]=[];
out.push(level('1-1','初生的孢子','valley','引一节芽，决定第一段路','小花在缺口那边等你。点亮根台，再选择根须向哪里长。',3,[...rect(-2,-1,3,3),...rect(2,-1,3,3),...rect(-1,2,2,2)],[mark('root',0,0,'引导根芽','root'),mark('core',3,0,'种下第一束微光','core')],[],[{id:'root',at:cell(0,0),budget:1,sockets:[[1,0],[0,1]],goal:[1,0],h:0}]));
out.push(level('1-2','第一朵花','valley','四节芽，自己绕过岩石','根种只有四节。可以从岩石上方或下方绕到花床，两条路都能开花。',3,[...rect(-2,0,3,3),...rect(4,0,3,3)],[mark('root',0,1,'安排根线','root'),mark('core',5,1,'照料第一朵花','core')],[],[{id:'root',at:cell(0,1),budget:4,sockets:[[1,1],[1,0],[2,0],[3,0],[3,1],[1,2],[2,2],[3,2],[4,1]],goal:[3,1],h:0}],cell(0,1)));
// The growth puzzle uses a two-cell-wide gap with a central rock: S(1,1), T(3,1).
out[1].roots[0]={id:'root',at:cell(1,1),budget:4,sockets:[[1,0],[2,0],[3,0],[3,1],[1,2],[2,2],[3,2]],goal:[3,1],h:0};
out[1].tiles=[...rect(-1,0,3,3),...rect(3,0,3,3)].filter(t=>!(t.x===1&&(t.z===0||t.z===2))&&!(t.x===3&&(t.z===0||t.z===2)));
out[1].marks[0].tile=cell(1,1);out[1].marks[1].tile=cell(4,1);out[1].walls=[[2,1]];
out.push(level('1-3','苔藓山谷','valley','连人带花园转向','走上中央庭院，再转动它。你的脚下、伙伴和出口都会一起改变。',4,[...rect(-5,-1,3,3),...rect(-1,-5,3,3),...rect(-1,3,3,3),...rect(3,-1,3,3)],[moduleMark('turn','garden','转动庭院','turn'),mark('core',0,-4,'照料山顶花床','core')],[{id:'garden',x:0,z:0,h:0,shape:elbow,kind:'rotate'}],[],cell(-4,0)));
out.push(level('1-4','鼹鼠的家','valley','换手，让同伴也能帮助你','露薇扳住重杆，小苔灵穿过低拱。两个人的位置，决定彼此能走的路。',4,[...rect(-4,-1,3,3),...rect(2,-1,3,3),...rect(2,4,3,3),...rect(-4,4,3,3),...path([[3,1],[3,4]],0,true)],[mark('hold',-3,0,'扳住重杆','lever'),mark('plate',3,5,'轻叶踏板','plate'),mark('latch',-3,5,'固定归途门闩','latch'),mark('bell',-2,5,'门铃','item'),mark('home',-4,0,'归还鼹鼠的门铃','flower'),mark('core',-4,-1,'一起照料家门','core')],[],[],cell(-3,0),true));
out[3].buddy=cell(-2,0);
out[3].sanctuary={gate:{id:cell(-6,0),x:-6,z:0,h:0},tiles:[...rect(-11,-2,5,5),...rect(-5,0,1,1)],fountain:{x:-9,z:-2,h:0}};
out[3].marks.find(m=>m.id==='core')!.tile=cell(-9,0);
out[3].marks.find(m=>m.id==='core')!.label='在花园中央种下微光';
out.push(level('2-1','池塘之声','pond','水位改变整片池塘','低位能取清露，中位连到花岸，高位还有芦苇湾。更高不一定更接近终点。',4,[...rect(-5,-1,3,3),...rect(3,-1,3,3,1),...rect(-1,-5,3,3,2),...path([[-4,0],[-4,4],[0,4],[0,2]])],[moduleMark('water','float','调节池塘水位','valve'),mark('dew',0,4,'接一滴清露','item'),moduleMark('care','float','把清露留给睡莲','flower'),mark('core',4,0,'唤醒池塘花床','core')],[lift('float',0,0)],[],modCell('float')));
out.push(level('2-2','涟漪之谜','pond','跟随发光镜叶，把光送到花床','先找发光的镜叶，再跟着箭头搬到叶形光槽。转动两片镜叶，让光绕过石壁。',5,rect(-1,-1,7,5),[mark('source',0,1,'固定光源','lamp'),mark('mirrorA',1,1,'① 固定反光叶','turn'),mark('mirrorB',4,3,'搬起第二片镜叶','item'),mark('slot',1,0,'② 镜叶光槽','slot'),mark('core',4,0,'接住绕过石壁的光','core')],[],[],cell(0,2)));
out[5].walls=[[2,1]];out[5].tiles=out[5].tiles.filter(t=>!(t.x===2&&t.z===1));
out.push(level('2-3','雨滴节拍','pond','写一段花园会跳的舞','安排转庭、升台、停拍的顺序。试奏可以暂停、单步，错了就重新排练。',4,[...rect(-5,-1,3,3),...rect(-1,-5,3,3,2)],[mark('song',-4,0,'雨滴琴与动作叶','song'),moduleMark('stage','stage','乘上花台','flower'),mark('latch',0,-4,'固定会合便道','latch'),mark('core',1,-4,'一起听雨','core')],[{id:'stage',x:0,z:0,h:0,shape:elbow,kind:'rotate'}],[],cell(-4,0),true));
out[6].buddy=cell(-4,1);
out.push(level('2-4','池塘守护者','pond','让花园载光虫回家','光虫愿意停在蜜花上。先载它越过池塘，再邀请它为远岸授粉。',5,[...rect(-5,-1,3,3),...rect(9,-1,3,3)],[mark('pollen',-4,0,'花粉与光虫','flower'),moduleMark('plant','boat','种一朵蜜花','flower'),moduleMark('slide','boat','移动花园','turn'),moduleMark('invite','boat','邀请光虫','flower'),mark('core',10,0,'照料授粉后的花岸','core')],[{id:'boat',x:0,z:0,h:0,shape:deck,kind:'slide',axis:'x',distance:6}],[],cell(-4,0)));
out.push(level('3-1','微光引路','cave','把光交给你，也把路交给你','小苔灵可以带灯穿低拱。露薇需要那束光，才能走到石窗另一边。',5,[...rect(-4,-1,3,3),...rect(2,-1,3,3),...rect(2,4,3,3),...rect(-4,4,3,3),...path([[-3,1],[-3,5],[2,5]],0,true)],[mark('lamp',-3,0,'暖灯','item'),mark('socket',3,5,'朝向接收叶的照孔','slot'),mark('window',3,0,'移开石窗','lever'),mark('core',4,0,'把微光留在灯井','core')],[],[],cell(-3,0),true));
out[8].buddy=cell(-2,0);
out.push(level('3-2','影子的形状','cave','把两个时刻拼成同一条路','留影苔只能记住一段路。先保留日影或月影都可以，再接上另一段。',5,[...rect(-2,-1,3,3),...rect(2,-1,2,2),...rect(2,3,3,3)],[mark('mode',-1,0,'切换日月','valve'),mark('freeze',-1,1,'留住当前投影','flower'),mark('core',3,4,'穿过相接的影路','core')],[],[],cell(0,0)));
out.push(level('3-3','共生之歌','cave','转一下，路与水都会变','两股水照顾三处生命。先让藤根学会蓄水，再把水让给花台与苔藓。',6,[...rect(-5,-1,3,3),...rect(-1,-5,3,3),...rect(7,-1,3,3,2),...rect(-1,3,3,3,2)],[moduleMark('turn','water','转动分水庭院','turn'),mark('root',0,-4,'引芽接往花台','root'),mark('care',1,-4,'把露珠留给藤根','flower'),moduleMark('lift','lift','调节水力花台','valve'),mark('dew',8,0,'高处露珠','item'),mark('core',0,4,'共生花床','core')],[{id:'water',x:0,z:0,h:0,shape:elbow,kind:'rotate'},lift('lift',4,0)], [{id:'root',at:cell(1,-4),budget:4,sockets:[[2,-4],[3,-4],[4,-4],[4,-3]],goal:[4,-3],h:0}],cell(-4,0)));
out.push(level('3-4','沉睡的守护者','cave','把一座花园安排成一个家','先固定根阶，再让水托起镜叶。最后让路、水与光同时到达中心。',8,[...rect(-5,-1,3,3),...rect(-1,-5,3,3),...rect(7,-1,3,3,2),...rect(-1,7,3,3),...path([[-4,0],[-4,8],[0,8]],0,true)],[moduleMark('inner','inner','转动内庭','turn'),mark('root',0,-4,'固定叶阶','root'),mark('mirror',1,-4,'重镜叶','item'),moduleMark('water','water','调整送水庭','valve'),moduleMark('lift','lift','升起载物花台','valve'),mark('highslot',8,0,'高处镜叶槽','slot'),moduleMark('light','light','调整外庭反光','turn'),mark('core',-4,0,'一起种下微光','core')],[{id:'inner',x:0,z:0,h:0,shape:elbow,kind:'rotate'},lift('lift',4,0),{id:'water',x:0,z:8,h:0,shape:deck,kind:'rotate',small:true},{id:'light',x:8,z:4,h:2,shape:deck,kind:'slide',axis:'z',distance:-4}], [{id:'root',at:cell(1,-4),budget:3,sockets:[[2,-4],[3,-4],[4,-4]],goal:[4,-4],h:0}],cell(-4,0),true));
out[11].buddy=cell(-3,0);out[11].collectibles=[];
const stories=['露薇种下第一节路，小花朝她靠近了一点。','根系绕过石头，一条由你安排的小路开满了花。','花园转向远方，伙伴仍稳稳站在你身旁。','门铃响起，鼹鼠为两位小邻居留着门。','睡莲接住清露，也接住两双小小的脚。','光绕过石壁，照见一朵等了很久的花。','花园跟着你写的雨歌，轻轻跳了一支舞。','小花园载回光虫，这里又可以成为家。','你把光交给伙伴，伙伴把一段路交给你。','不同的时刻，在同一条归途上相遇。','藤根学会照顾自己，把水留给了其他生命。','路、水与光相连，露薇和小苔灵一起回家。'];
out[0].tiles=out[0].tiles.filter(t=>t.z!==1);
out[11].tiles=out[11].tiles.filter(t=>!(t.x>=-1&&t.x<=1&&t.z>=7&&t.z<=9));
out[11].tiles.forEach(t=>{if(t.x===-4&&t.z<=1)t.small=false;});
out.forEach((l,i)=>{
 l.story=stories[i];
 const rest=l.tiles.find(t=>t.id!==l.start&&!l.marks.some(m=>m.tile===t.id))!;
 const observe=[...l.tiles].reverse().find(t=>!l.marks.some(m=>m.tile===t.id)&&t.id!==rest.id)!;
 l.marks.push({id:'rest',tile:rest.id,label:'在这里坐一会儿',kind:'rest',text:'没有需要赶上的时间。小苔灵靠着你，听风从石阶间经过。'},{id:'observe',tile:observe.id,label:'看看这里的小生命',kind:'observe',text:l.story});
 // Fill each exact collection budget with distinct, stable, reachable floor identities.
 if(l.id!=='3-4'){const valid=new Set([...l.tiles.map(t=>t.id),...l.modules.flatMap(m=>m.shape.map(([x,z])=>modCell(m.id,x,z)))]);const candidates=[...l.collectibles.map(c=>c.tile),...l.tiles.map(t=>t.id)].filter(t=>valid.has(t)&&t!==l.start&&!l.walls?.some(([x,z])=>t===cell(x,z)));l.collectibles=[...new Set(candidates)].slice(0,l.total).map((tile,n)=>({id:`spore-${n}`,tile}));}
});
export const GARDEN_LEVELS=out;
export const gardenLevel=(id:string)=>GARDEN_LEVELS.find(l=>l.id===id)??GARDEN_LEVELS[0];
for(const id of ['3-3','3-4'])out.find(l=>l.id===id)!.modules[0].shape=[[0,0],[-1,0],[-2,0],[0,-1],[0,-2]];
out[11].modules.find(m=>m.id==='light')!.kind='rotate';
out[11].modules.find(m=>m.id==='light')!.shape=[[0,0],[-1,0],[-2,0],[0,-1],[0,-2]];
out[11].modules.find(m=>m.id==='water')!.shape=elbow;
out.forEach((l,i)=>{if(i>=3)l.dual=true;});
out[0].collectibles=[cell(-2,-1),cell(-1,0),cell(0,2)].map((tile,n)=>({id:`spore-${n}`,tile}));
out[9].marks.push(mark('sunSlot',0,0,'日影柱槽','slot'),mark('moonSlot',3,-1,'月影柱槽','slot'));
out[9].marks.push(mark('sunPost',-2,0,'日影柱','item'),mark('moonPost',-2,1,'月影柱','item'));

// Broad terraces keep the existing tile identities and puzzle connections.
// A one-level change is a real walkable stair; larger gaps still need a mechanism.
for(const l of out.filter(l=>l.chapter==='valley'))for(const t of l.tiles){
 if(l.id==='1-1')t.h=t.x>=2?(t.z===-1?2:1):t.z>=2?-1:0;
 if(l.id==='1-2')t.h=t.x===3&&t.z===1?0:t.x>=3?(t.z===0?2:1):0;
 if(l.id==='1-3')t.h=t.z<=-3?1:t.x>=3?-1:0;
}
if(out[3].sanctuary){
 const garden=out[3].sanctuary;garden.gate.h=1;garden.fountain.h=1;
 garden.tiles.forEach(t=>t.h=t.x<=-10?2:t.x<=-7?1:0);
}
// Shallow brooks retain fixed stepping stones and the existing movement graph.
for(const l of out.filter(l=>l.chapter==='pond'))for(const t of l.tiles){
 if(l.id==='2-1'&&t.z>=2&&t.x>=-2)t.kind='water';
 if(l.id==='2-2'&&t.z===2)t.kind='water';
 if(l.id==='2-4'&&(t.x===-3||t.x===9))t.kind='water';
}
