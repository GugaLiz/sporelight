import type {GardenLevel,Point,Tile} from './types';
export interface Scenery extends Point {asset:string;width:number;depth?:number}
export const GARDEN_SCENERY_ASSETS=['dew-plant','dew-parcel','berry-bush','river-rock','pebble-cluster','small-pebbles','stone-lantern','gold-lotus','trailing-vine','pink-flowers','ivory-lotus','glow-flower','fern','blue-flowers','yellow-flowers','red-mushroom','blue-mushroom','wood-lantern','violet-crystal','light-tower','lotus-pool'];

/** Stable patches blend supplied grass, moss and paving; working platforms stay clear. */
export function terrainSurface(level:GardenLevel,tile:Tile){
 const stone=level.chapter==='pond'?'paving-pond':'paving-valley';
 if(tile.kind==='water'||tile.kind==='module'||tile.kind==='shadow')return stone;
 if(tile.small||tile.kind==='root')return 'paving-grass';
 if(level.marks.some(m=>m.tile===tile.id&&!['rest','observe'].includes(m.kind)))return stone;
 const patch=(Math.floor((tile.x+30)/2)*3+Math.floor((tile.z+30)/2)*5+Number(level.id.slice(-1)))%8;
 if(patch<(level.chapter==='valley'?3:1))return 'paving-grass';
 return patch<5?'paving-moss':stone;
}

/** Props sit at the rim, with space around puzzle targets, footsteps and root sockets. */
export function gardenScenery(level:GardenLevel):Scenery[]{
 const palette=level.chapter==='valley'?['berry-bush','fern','small-pebbles','pink-flowers','stone-lantern','yellow-flowers','red-mushroom','blue-flowers','gold-lotus','bush']:level.chapter==='pond'?['fern','river-rock','blue-flowers','ivory-lotus','berry-bush','yellow-flowers','lotus-pool','pink-flowers','stone-lantern']:['blue-mushroom','small-pebbles','fern','violet-crystal','stone-lantern','blue-flowers','glow-flower'];
 const landmarks=level.marks.filter(m=>!['rest','observe'].includes(m.kind)).map(m=>level.tiles.find(t=>t.id===m.tile)).filter(Boolean) as Point[];
 const approaches=level.modules.flatMap(m=>m.shape.flatMap(([x,z])=>Array.from({length:m.kind==='rotate'?4:m.kind==='slide'?2:1},(_,n)=>{
  let dx=x,dz=z;if(m.kind==='rotate')for(let i=0;i<n;i++)[dx,dz]=[-dz,dx];
  return {x:m.x+dx+(m.axis==='x'?n*(m.distance??0):0),z:m.z+dz+(m.axis==='z'?n*(m.distance??0):0)};
 })));
 const directions=[[-1,0],[0,-1],[1,0],[0,1]],widths:Record<string,number>={'berry-bush':39,bush:39,'small-pebbles':25,'river-rock':30,'pebble-cluster':29,'stone-lantern':30,'lotus-pool':47,'gold-lotus':32};
 const candidates=level.tiles.filter(t=>!t.small&&!t.solid&&t.kind!=='water'&&t.id!==level.start&&t.id!==level.buddy&&!level.collectibles.some(c=>c.tile===t.id)&&!landmarks.some(p=>Math.abs(t.x-p.x)+Math.abs(t.z-p.z)<2)&&!approaches.some(p=>Math.abs(t.x-p.x)+Math.abs(t.z-p.z)<=1)&&!level.roots.some(r=>r.sockets.some(([x,z])=>Math.abs(x-t.x)+Math.abs(z-t.z)<=1))&&directions.some(([dx,dz])=>!level.tiles.some(p=>p.x===t.x+dx&&p.z===t.z+dz))).sort((a,b)=>a.x+a.z-b.x-b.z);
 const decorations:Scenery[]=[];
 for(const t of candidates){
  if(decorations.length>=13||decorations.some(p=>Math.abs(p.x-t.x)+Math.abs(p.z-t.z)<1.3))continue;
  const edge=directions.find(([dx,dz])=>!level.tiles.some(p=>p.x===t.x+dx&&p.z===t.z+dz))!,i=decorations.length,asset=palette[(i+Number(level.id.slice(-1))*2)%palette.length];
  decorations.push({...t,x:t.x+edge[0]*.24,z:t.z+edge[1]*.24,depth:t.x+t.z+.12,asset,width:widths[asset]??(i%3===0?35:30)});
 }
 if(level.sanctuary){
  const flowers=['pink-flowers','blue-flowers','yellow-flowers','ivory-lotus','gold-lotus'];let n=0;
  for(const x of [-11,-9,-7])for(const z of [-2,2])if(!(x===-9&&z===-2)){const asset=flowers[n++%flowers.length];decorations.push({x,z,h:level.sanctuary.tiles.find(t=>t.x===x&&t.z===z)?.h??0,asset,width:42});}
  decorations.push({x:-11,z:0,h:level.sanctuary.tiles.find(t=>t.x===-11&&t.z===0)?.h??0,asset:'berry-bush',width:46});
  decorations.push({x:-7,z:-1.7,h:1,asset:'stone-lantern',width:29});
 }
 if(['1-3','2-4','3-4'].includes(level.id)){const t=level.tiles.find(t=>!landmarks.some(p=>Math.abs(p.x-t.x)+Math.abs(p.z-t.z)<2)&&!t.small&&!decorations.some(p=>Math.abs(p.x-t.x)+Math.abs(p.z-t.z)<1));if(t)decorations.push({...t,asset:level.chapter==='cave'?'light-tower':level.chapter==='valley'?'arch':'wood-lantern',width:level.chapter==='valley'?90:level.chapter==='cave'?65:40});}
 return decorations;
}
