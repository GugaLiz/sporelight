import type {GardenState} from './types';
export function moleDialogue(state:GardenState){
 if(state.completed)return {stage:'restored',text:'花开啦，连蝴蝶都来做客了。以后也常来坐坐呀。'};
 if(state.flags.includes('home'))return {stage:'welcome',text:'谢谢你们！花门开了，带上小伙伴去喷泉边看看吧。'};
 if(state.items.bell?.holder)return {stage:'bell',text:'咦，是我的小门铃！我认得这声轻轻的叮铃。'};
 if(state.flags.includes('latch'))return {stage:'latch',text:'回来的路修好啦。门铃好像落在那边的石台上了……'};
 if(state.flags.includes('hold'))return {stage:'help',text:'你们配合得真好！小拱道就拜托小苔灵啦。'};
 return {stage:'lost',text:'雨把我的门铃吹跑了……你们愿意帮我找找吗？'};
}

/** Conversations belong to a visit, never to the puzzle's saved state. */
export class MoleConversation{
 private stage='';private wasNear=false;private until=0;private nextGreeting=0;private text='';
 update(state:GardenState,near:boolean,time:number){
  if(!near){this.wasNear=false;return;}
  const line=moleDialogue(state);
  if(line.stage!==this.stage||!this.wasNear&&time>=this.nextGreeting){
   this.stage=line.stage;this.text=line.text;this.until=time+8000;this.nextGreeting=time+20000;
  }
  this.wasNear=true;
  if(time<this.until)return this.text;
 }
}
