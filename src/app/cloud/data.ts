export type CloudLevelId = 'cloud-1' | 'cloud-2' | 'cloud-3';
export interface Point { x:number; z:number; h:number }
export interface CloudTile extends Point { id:string; kind:'floor'|'stair'|'bridge'|'lift'|'gate' }
export interface Landmark extends Point { id:string; label:string; icon:string; story?:string }
export interface CloudLevel {
  id:CloudLevelId; title:string; subtitle:string; accent:string; sky:[string,string]; start:string;
  landmarks:Landmark[]; story:string; restored:string;
}
export const CLOUD_LEVELS:CloudLevel[] = [
  {id:'cloud-1',title:'风眠拱庭',subtitle:'让一座沉睡的钟塔，重新开花。',accent:'#d69b8a',sky:['#f5e8de','#c3d5cc'],start:'floor:1:7',
    landmarks:[
      {id:'turn',x:4,z:3,h:1,label:'转动拱桥',icon:'↻'},
      {id:'seed',x:4,z:-3,h:1,label:'拾起花种',icon:'❋'},
      {id:'finish',x:10,z:3,h:1,label:'种下第一束微光',icon:'✧'},
      {id:'wind',x:1,z:8,h:0,label:'听听风',icon:'❧',story:'风从拱门穿过，像有人轻轻说：慢慢来，花会等你。'},
      {id:'letter',x:3,z:-4,h:1,label:'读一封旧信',icon:'✉',story:'「如果你找到了这粒种子，请把它种在能看见远方的地方。」信纸上有小小的爪印。'},
    ],story:'露薇把花种埋在钟塔下。第一朵花开放的时候，一团苔藓打了个哈欠。从今天起，路上多了一双小脚印。',restored:'风终于有了可以停留的地方。'},
  {id:'cloud-2',title:'浮水花院',subtitle:'接住一池雨，把温柔送到高处。',accent:'#82aeb8',sky:['#e6eff0','#b8d2cf'],start:'floor:1:7',
    landmarks:[
      {id:'dock',x:5,z:4,h:0,label:'呼唤花台',icon:'↕'},
      {id:'valve',x:6,z:4,h:0,label:'升降花阀',icon:'↕'},
      {id:'finish',x:10,z:4,h:3,label:'引水入花池',icon:'≈'},
      {id:'rain',x:1,z:8,h:0,label:'收听雨的来信',icon:'☂',story:'石碗里留着昨夜的一点雨。小苔灵低头照了照，发现水里也有一个圆滚滚的自己。'},
      {id:'bird',x:11,z:5,h:3,label:'留一片叶子',icon:'❧',story:'露薇把一片叶子放在池边。也许会有一只小鸟，愿意把这里当作歇脚的家。'},
    ],story:'花台托起露薇，也托起一池被遗忘的雨。水流重新唱歌，小鸟落在池边，小苔灵的脚尖溅起一颗小星星。',restored:'水记得回家的方向。'},
  {id:'cloud-3',title:'星灯归舍',subtitle:'有你等在这里，远处的灯就不再孤单。',accent:'#afa2cc',sky:['#e6e1f0','#afbdce'],start:'floor:1:7',
    landmarks:[
      {id:'pad',x:3,z:6,h:1,label:'请小苔灵等一等',icon:'❧'},
      {id:'latch',x:8,z:6,h:1,label:'打开归途门闩',icon:'⌘'},
      {id:'turn',x:8,z:5,h:1,label:'转动星桥',icon:'↻'},
      {id:'finish',x:8,z:0,h:1,label:'一起点亮星灯',icon:'✧'},
      {id:'home',x:1,z:8,h:1,label:'看看小小的家',icon:'⌂',story:'门边留着两双拖鞋。一双很小，另一双更小。原来「回家」可以是为另一个人留一盏灯。'},
      {id:'star',x:14,z:5,h:1,label:'捡一颗纸星星',icon:'☆',story:'这里藏着一颗折得歪歪的纸星星。小苔灵坚持说，那是天空掉下来的。'},
    ],story:'露薇没有一个人走向星灯。她回头，接上等在门边的小伙伴。三座庭院亮了起来，屋顶上并排坐着两个小小的身影。',restored:'有人陪你走的路，就是归途。'},
];
export const cloudLevel=(id:string)=>CLOUD_LEVELS.find(l=>l.id===id)??CLOUD_LEVELS[0];
export const tileId=(x:number,z:number,kind='floor')=>`${kind}:${x}:${z}`;

/** Stable tile IDs survive height changes. The same physical graph drives drawing and walking. */
export function cloudTiles(id:CloudLevelId,bridge:'north'|'east',lift:'low'|'high',gate:boolean):CloudTile[] {
  const tiles=new Map<string,CloudTile>();
  const add=(x:number,z:number,h:number,kind:CloudTile['kind']='floor')=>{const tile={id:tileId(x,z,kind),x,z,h,kind};tiles.set(tile.id,tile);};
  const rect=(x1:number,z1:number,x2:number,z2:number,h:number,kind:CloudTile['kind']='floor')=>{for(let x=x1;x<=x2;x++)for(let z=z1;z<=z2;z++)add(x,z,h,kind);};
  if(id==='cloud-1'){
    rect(0,6,3,8,0);add(3,5,0,'stair');add(3,4,1,'stair');rect(3,2,5,3,1);add(4,4,1);add(5,4,1);
    rect(3,-4,5,-2,1);rect(9,2,11,4,1);
    if(bridge==='north')rect(4,-1,4,1,1,'bridge');else rect(6,3,8,3,1,'bridge');
  }else if(id==='cloud-2'){
    rect(0,6,3,8,0);rect(3,3,5,5,0);rect(8,3,11,5,3);rect(6,3,7,4,lift==='low'?0:3,'lift');
  }else{
    rect(0,6,3,8,1);rect(7,5,9,7,1);rect(7,-1,9,1,1);rect(13,4,14,6,1);
    if(gate)rect(4,6,6,6,1,'gate');
    if(bridge==='north')rect(8,2,8,4,1,'bridge');else rect(10,5,12,5,1,'bridge');
  }
  return [...tiles.values()];
}
