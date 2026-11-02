export type Actor='luvie'|'buddy';
export interface Point{x:number;z:number;h:number}
export interface Tile extends Point{id:string;kind?:'root'|'module'|'shadow'|'water';module?:string;local?:[number,number];small?:boolean;solid?:boolean}
export interface Item{tile:string;holder?:Actor;angle:number;picked?:boolean}
export interface GardenState{designVersion:2;levelId:string;active:Actor;actors:Record<Actor,string>;follow:boolean;growth:Record<string,string[]>;turns:Record<string,number>;flags:string[];items:Record<string,Item>;collected:string[];observations:string[];discovered?:string[];water:number;mode:0|1;frozen:number|null;shadowMemory?:Point[];song:string[];beat:number;playing:boolean;trial?:string;completed:boolean}
export interface Module{id:string;x:number;z:number;h:number;shape:[number,number][];kind:'rotate'|'lift'|'slide';axis?:'x'|'z';distance?:number;low?:number;high?:number;small?:boolean}
export interface Root{id:string;at:string;budget:number;sockets:[number,number][];goal:[number,number];h:number}
export interface Landmark{id:string;tile:string;label:string;kind:'core'|'root'|'turn'|'valve'|'lever'|'plate'|'latch'|'item'|'slot'|'song'|'lamp'|'flower'|'rest'|'observe';text?:string}
export interface Collectible{id:string;tile:string;when?:string}
export interface GardenLevel{id:string;title:string;chapter:'valley'|'pond'|'cave';rule:string;intro:string;story:string;total:number;tiles:Tile[];modules:Module[];roots:Root[];marks:Landmark[];collectibles:Collectible[];start:string;buddy?:string;dual?:boolean;walls?:[number,number][];sanctuary?:{gate:Tile;tiles:Tile[];fountain:Point}}
export interface Command{id:string;label:string;selected?:boolean;target?:string}
export const cell=(x:number,z:number)=>`f:${x}:${z}`;
export const modCell=(m:string,x=0,z=0)=>`m:${m}:${x}:${z}`;
export const DIRECTION={up:[0,-1],right:[1,0],down:[0,1],left:[-1,0]} as const;
