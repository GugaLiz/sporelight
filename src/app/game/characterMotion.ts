export type Facing = 'left' | 'right' | 'front' | 'back';
export type CharacterAction = { kind: 'sow' | 'interact' | 'note' | 'symbiosis'; startedAt: number };
export interface MotionInput {
  time: number;
  facing: Facing;
  lowMotion: boolean;
  complete: boolean;
  travel?: { progress: number; startedAt: number; jump: boolean; rolling: boolean; distance: number } | null;
  action?: CharacterAction | null;
}
export interface CharacterPose { key: string; clip: string; flip: boolean; rotation: number; scaleX: number; scaleY: number; offsetY: number }
export const CHARACTER_FILES = ['idle-front','idle-side','idle-back','idle-quarter','jump','interact','ball','lean','salute','symbiosis',...Array.from({length:6},(_,i)=>`walk-${i+1}`),...Array.from({length:5},(_,i)=>`sow-${i+1}`)];

export function facingFor(dx: number, dy: number): Facing {
  if (Math.abs(dy) > Math.abs(dx) * .85) return dy < 0 ? 'back' : 'front';
  return dx > 0 ? 'right' : 'left';
}
export function jumpHeight(progress: number, lowMotion: boolean) {
  return lowMotion ? 0 : Math.sin(Math.max(0,Math.min(1,progress))*Math.PI)*85;
}

export function characterPose(input: MotionInput): CharacterPose {
  const pose: CharacterPose = {key:'idle-front',clip:'idle',flip:false,rotation:0,scaleX:1,scaleY:1,offsetY:0};
  const {time,facing,travel,action,lowMotion}=input;
  if (input.complete) return {...pose,key:'salute',clip:'bow'};
  if (lowMotion) return pose;
  if (travel) {
    const elapsed=Math.max(0,time-travel.startedAt);
    if (travel.jump) {
      const p=travel.progress;
      const landing=p>.8?Math.sin((p-.8)/.2*Math.PI):0;
      return {...pose,key:p<.14?'lean':'jump',clip:p<.14?'takeoff':p>.8?'landing':'jump',flip:facing==='right',rotation:Math.sin(p*Math.PI)*.06*(facing==='left'?-1:1),scaleX:1+landing*.12,scaleY:1-landing*.12};
    }
    if (travel.rolling) return {...pose,key:'ball',clip:'roll',rotation:travel.progress*travel.distance/32*(facing==='left'?-1:1),scaleX:.8,scaleY:.8};
    if (facing==='back') return {...pose,key:'idle-back',clip:'walk-back',offsetY:-Math.abs(Math.sin(elapsed/110*Math.PI))*2,rotation:Math.sin(elapsed/110*Math.PI)*.025};
    return {...pose,key:`walk-${1+Math.floor(elapsed/110)%6}`,clip:'walk',flip:facing==='right',offsetY:-Math.abs(Math.sin(elapsed/110*Math.PI))*1.5};
  }
  if (action) {
    const elapsed=time-action.startedAt;
    if (elapsed>=0 && elapsed<900) {
      if (action.kind==='symbiosis') return {...pose,key:'symbiosis',clip:'symbiosis'};
      if (action.kind==='sow') return {...pose,key:`sow-${1+Math.min(4,Math.floor(elapsed/140))}`,clip:'sow',flip:facing==='left'};
      return {...pose,key:action.kind==='note'?'lean':'interact',clip:action.kind,flip:facing==='right',offsetY:action.kind==='note'?-Math.sin(Math.min(1,elapsed/450)*Math.PI)*3:0};
    }
  }
  pose.key=facing==='back'?'idle-back':facing==='left'||facing==='right'?'idle-side':'idle-front';
  pose.flip=facing==='right';
  const breath=Math.sin(time/700);
  pose.scaleY=1+breath*.012;pose.scaleX=1-breath*.006;
  return pose;
}
