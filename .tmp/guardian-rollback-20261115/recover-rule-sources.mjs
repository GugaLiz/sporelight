import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root=process.cwd();
const session='C:/Users/jeffrey/.codex/sessions/2026/11/15/rollout-2026-11-15T11-21-35-01a1dd39-7f9b-7662-bb14-d81895112bd1.jsonl';
// Access only plaintext tool call/output payloads. Do not inspect reasoning.
const records=fs.readFileSync(session,'utf8').split('\n').filter(Boolean).map(JSON.parse).filter(r=>r.type==='response_item'&&['custom_tool_call','custom_tool_call_output'].includes(r.payload?.type));
const outputs=new Map(records.filter(r=>r.payload.type==='custom_tool_call_output').map(r=>[r.payload.call_id,r.payload.output]));
const textOf=o=>Array.isArray(o)?o.filter(b=>b.type==='input_text').map(b=>b.text).join('\n'):String(o);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const proof=JSON.parse(fs.readFileSync('docs/qa-godot-native/guardian-causality-20261115/gpu-candidate1/checks.json','utf8')).initialSources;
const out=path.join(root,'.tmp/guardian-rollback-20261115/recovered/godot');
const reports=[];
function writeVerified(rel,content,origin){
 const expected=proof[rel];
 if(sha(content)!==expected)throw new Error('hash mismatch '+rel+' got '+sha(content)+' expected '+expected);
 const target=path.join(out,rel);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);
 reports.push({file:rel,sha256:sha(content),expected,matched:true,origin});
}
// Extract the original JSON bytes directly from the immutable format-4 PCK.
const pck=fs.readFileSync('godot/build/guardian-causality-20261115-release/index.pck');
const base=Number(pck.readBigUInt64LE(24));let cursor=Number(pck.readBigUInt64LE(32));const count=pck.readUInt32LE(cursor);cursor+=4;
for(let i=0;i<count;i++){
 const len=pck.readUInt32LE(cursor);cursor+=4;const name=pck.subarray(cursor,cursor+len).toString('utf8').replace(/\0+$/,'');cursor+=len;
 const offset=Number(pck.readBigUInt64LE(cursor));cursor+=8;const size=Number(pck.readBigUInt64LE(cursor));cursor+=8;cursor+=20;
 if(name==='content/levels.json')writeVerified(name,pck.subarray(base+offset,base+offset+size),'target PCK raw resource');
}
const readouts=[];
for(const r of records.filter(r=>r.payload.type==='custom_tool_call_output')){
 for(const block of Array.isArray(r.payload.output)?r.payload.output:[]){
  if(block.type!=='input_text')continue;
  try{const value=JSON.parse(block.text);if(typeof value.output==='string')readouts.push({id:r.payload.call_id,text:value.output.replace(/\r\n/g,'\n')});}catch{}
 }
}
function variants(text){const normal=text.replace(/\r\n/g,'\n');const result=[normal,normal.replace(/\n/g,'\r\n'),normal.replace(/\n?$/,'\n'),normal.replace(/\n?$/,'\n').replace(/\n/g,'\r\n')];
 const a=normal.indexOf('func _guardian_hint()'),b=normal.indexOf('func mirror_guidance()',a);
 if(a>=0&&b>a){for(const da of [-2,-1,0])for(const db of [-1,0,1]){const start=a+da,end=b+db;result.push(normal.slice(0,start).replace(/\n/g,'\r\n')+normal.slice(start,end)+normal.slice(end).replace(/\n/g,'\r\n'));}
  const prior=records.find(r=>r.payload.call_id==='call_4fe06567f752453298aeaa1058a3dc35'&&r.payload.type==='custom_tool_call');
  const m=prior?.payload.input.match(/tools\.apply_patch\(("(?:[^"\\]|\\.)*")\)/);const added=new Set(m?JSON.parse(m[1]).split('\n').filter(l=>l.startsWith('+')&&!l.startsWith('+++')).map(l=>l.slice(1)):[]);
  const lines=normal.slice(a,b).split('\n');
  for(const oldEnd of ['\n','\r\n'])for(const newEnd of ['\n','\r\n']){
   const hint=lines.slice(0,-1).map(l=>l+(added.has(l)?newEnd:oldEnd)).join('');
   result.push(normal.slice(0,a).replace(/\n/g,'\r\n')+hint+normal.slice(b).replace(/\n/g,'\r\n'));
  }
 }
 return [...new Set(result.flatMap(s=>[s,'\ufeff'+s]))];}
let restoredFlow=false;
for(const r of readouts){
 const start=r.text.indexOf('extends RefCounted\n## Current intentions and object names');
 if(start<0)continue;
 const remaining=r.text.slice(start);const endLine='\treturn "根路接通、首次供水、首次接光、花坛会合，各得到两份赠礼；无需另找收藏。"';
 const end=remaining.indexOf(endLine);if(end<0)continue;
 const candidate=remaining.slice(0,end+endLine.length)+'\n';
 for(const variant of variants(candidate))if(sha(variant)===proof['application/guardian_flow_guidance.gd']){writeVerified('application/guardian_flow_guidance.gd',variant,'plaintext complete read '+r.id);restoredFlow=true;break;}
 if(restoredFlow)break;
}
if(!restoredFlow)throw new Error('No exact Flow plaintext hash match');
let core=fs.readFileSync('godot/core/garden_world.gd','utf8').replace(/\r\n/g,'\n');
const patchRecords=[];
for(const r of records){
 if(r.payload.type!=='custom_tool_call'||r.timestamp<'2026-11-15T04:02:00Z'||r.timestamp>'2026-11-15T04:09:00Z')continue;
 const answer=textOf(outputs.get(r.payload.call_id));if(answer.includes('Script failed')||answer.includes('verification failed'))continue;
 for(const m of (r.payload.input??'').matchAll(/tools\.apply_patch\(("(?:[^"\\]|\\.)*")\)/g)){
  const patch=JSON.parse(m[1]);if(patch.includes('*** Update File: C:/Users/jeffrey/Documents/project/WebstormProjects/sporelight/godot/core/garden_world.gd'))patchRecords.push({id:r.payload.call_id,patch});
 }
}
for(const record of patchRecords.reverse()){
 const section=record.patch.split('*** Update File: C:/Users/jeffrey/Documents/project/WebstormProjects/sporelight/godot/core/garden_world.gd\n')[1].split('*** ')[0];
 const hunks=section.split(/^@@.*\n/m).filter(Boolean);
 for(const hunk of hunks.reverse()){
  const before=[],after=[];for(const line of hunk.replace(/\n$/,'').split('\n')){if(line.startsWith(' ')){before.push(line.slice(1));after.push(line.slice(1));}else if(line.startsWith('-'))before.push(line.slice(1));else if(line.startsWith('+'))after.push(line.slice(1));}
  const from=after.join('\n'),to=before.join('\n');
  if(!from){
   // Two recorded deletions had no retained context. Anchor their exact old
   // payload to the untouched following statement in that original function.
   const functionStart=core.indexOf(to.startsWith('\t\tif level.id == "3-4":')?'func tiles() -> Array:':'func rays() -> Array:');
   const following=to.startsWith('\t\tif level.id == "3-4":')?'\tfor module: Dictionary in level.modules:':'\tvar seen: Dictionary = {}';
   const anchor=core.indexOf(following,functionStart);if(anchor<0)throw new Error('missing deletion anchor');
   core=core.slice(0,anchor)+to+'\n'+core.slice(anchor);continue;
  }
  const at=core.indexOf(from);
  if(at<0||core.indexOf(from,at+1)>=0)throw new Error('nonunique reverse hunk '+record.id+' '+from.slice(0,100));
  core=core.slice(0,at)+to+core.slice(at+from.length);
 }
}
const hints=[];
for(const r of readouts){const a=r.text.indexOf('func _guardian_hint() -> String:');const b=r.text.indexOf('func mirror_guidance() -> Dictionary:',a);if(a>=0&&b>a&&r.text.slice(a,b).includes('高岸不能远程召台'))hints.push({id:r.id,text:r.text.slice(a,b)});}
let restoredCore=false;
for(const hint of hints){
 const a=core.indexOf('func _guardian_hint() -> String:');const b=core.indexOf('func mirror_guidance() -> Dictionary:',a);
 const candidate=core.slice(0,a)+hint.text+core.slice(b);
 fs.writeFileSync(path.join(root,'.tmp/guardian-rollback-20261115/core-reconstruction-candidate.gd'),candidate);
 for(const variant of variants(candidate))if(sha(variant)===proof['core/garden_world.gd']){writeVerified('core/garden_world.gd',variant,'reverse verified successful plaintext patches and original hint read '+hint.id);restoredCore=true;break;}
 if(restoredCore)break;
}
if(!restoredCore){
 const candidate=fs.readFileSync(path.join(root,'.tmp/guardian-rollback-20261115/core-reconstruction-candidate.gd'),'utf8').split('\n');
 const comparisons=[['call_810e09490b094190a9318cdf077aca2c',[[0,185],[540,190],[760,105]]],['call_5631017c378c4543b34b16a8cd10b3f0',[[177,155],[360,58],[494,47]]]];
 for(const [id,ranges] of comparisons){const original=readouts.find(r=>r.id===id)?.text.split('\n');if(!original)continue;let off=0;for(const [start,length]of ranges){for(let i=0;i<length;i++)if(original[off+i]!==candidate[start+i])console.log(JSON.stringify({read:id,line:start+i+1,expected:original[off+i],candidate:candidate[start+i]}));off+=length;}}
 throw new Error('Core hash mismatch after reverse; patches '+patchRecords.length+' hint candidates '+hints.length+' LF '+sha(core));
}
fs.writeFileSync(path.join(root,'.tmp/guardian-rollback-20261115/recovery-rules.json'),JSON.stringify({passed:true,targetSource:'fd9b143e88990629dfa3efa92b7ca7ebb91280ea18bac446a3266b5deacc9270',files:reports},null,2)+'\n');
console.log(JSON.stringify(reports,null,2));
