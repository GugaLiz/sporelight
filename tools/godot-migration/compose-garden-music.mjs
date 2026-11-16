import {mkdir, writeFile, readFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

// Original score and deterministic acoustic synthesis. No sampled recording,
// model service, downloaded instrument or third-party composition is used.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const option = (key, fallback) => process.argv.find(a => a.startsWith(`--${key}=`))?.slice(key.length + 3) ?? fallback;
const output = resolve(root, option('output', 'godot/assets/audio'));
const qa = resolve(root, option('qa', 'docs/qa-godot-native/garden-music-20261114'));
const python = option('python', 'python');
const codec = option('codec-path', '');
const rate = 32000, duration = 112, frames = rate * duration;
const seed = 0x53504f52;
let randomState = seed;
const random = () => ((randomState = (Math.imul(randomState, 1664525) + 1013904223) >>> 0) / 4294967296);
const stereo = count => [new Float32Array(count), new Float32Array(count)];
const midi = note => 440 * 2 ** ((note - 69) / 12);
const smooth = n => {const x = Math.max(0, Math.min(1, n)); return x * x * (3 - 2 * x);};
const db = value => 20 * Math.log10(Math.max(value, 1e-12));

function addNote(target, startSeconds, note, seconds, gain, timbre, pan = 0) {
  const frequency = midi(note), count = Math.ceil(seconds * rate), offset = Math.round(startSeconds * rate);
  const left = Math.cos((pan + 1) * Math.PI / 4), right = Math.sin((pan + 1) * Math.PI / 4);
  const phase = random() * Math.PI * 2;
  let string = null, cursor = 0;
  if (timbre === 'harp') {
    string = new Float64Array(Math.max(12, Math.round(rate / frequency)));
    let previous = 0;
    for (let i = 0; i < string.length; i++) {previous = previous * .65 + (random() * 2 - 1) * .35; string[i] = previous;}
    const mean = string.reduce((sum,value)=>sum+value,0)/string.length;
    for(let i=0;i<string.length;i++)string[i]-=mean;
  }
  for (let i = 0; i < count; i++) {
    const t = i / rate, angle = Math.PI * 2 * frequency * t;
    let sample = 0;
    if (timbre === 'strings') {
      const envelope = smooth(t / 1.8) * smooth((seconds - t) / 2.4);
      sample = envelope * (.66 * Math.sin(angle + phase) + .19 * Math.sin(angle * 1.0009 + phase * .7) + .09 * Math.sin(angle * 2) + .035 * Math.sin(angle * 3));
    } else if (timbre === 'harp') {
      sample = string[cursor];
      const next = (cursor + 1) % string.length;
      string[cursor] = .995 * .5 * (sample + string[next]); cursor = next;
      sample *= smooth(t / .006) * smooth((seconds - t) / .22) * 3.4;
    } else if (timbre === 'bass') {
      sample = smooth(t / .12) * Math.exp(-t / 2.9) * smooth((seconds - t) / .8) * (Math.sin(angle) + .12 * Math.sin(angle * 2));
    } else {
      const envelope = smooth(t / .018) * Math.exp(-t / 1.05) * smooth((seconds - t) / .35);
      sample = envelope * (Math.sin(angle) + .16 * Math.sin(angle * 2 + .02) * Math.exp(-t * 2) + .07 * Math.sin(angle * 3) * Math.exp(-t * 3) + .025 * Math.sin(angle * 5) * Math.exp(-t * 6));
    }
    let at = offset + i;
    if (at < 0) at += target[0].length;
    else if (at >= target[0].length) at -= target[0].length;
    if (at < 0 || at >= target[0].length) continue;
    target[0][at] += sample * gain * left;
    target[1][at] += sample * gain * right;
  }
}

function room(dry) {
  const wet = dry.map(channel => new Float32Array(channel));
  for (const [seconds, gain, cross] of [[.113,.13,true],[.229,.09,false],[.379,.06,true],[.557,.045,false],[.733,.03,true]]) {
    const shift = Math.round(seconds * rate), length = dry[0].length;
    for (let i = 0; i < length; i++) {
      const at = i >= shift ? i - shift : i + length - shift;
      wet[0][i] += dry[cross ? 1 : 0][at] * gain;
      wet[1][i] += dry[cross ? 0 : 1][at] * gain;
    }
  }
  return wet;
}

function metrics(channels) {
  let square = 0, peak = 0, clips = 0;
  for (const channel of channels) for (const sample of channel) {square += sample * sample; peak = Math.max(peak, Math.abs(sample)); if (Math.abs(sample) >= 1) clips++;}
  const rms = Math.sqrt(square / (channels.length * channels[0].length));
  return {frames:channels[0].length,channels:channels.length,sampleRate:rate,duration:channels[0].length/rate,peakDbFS:db(peak),rmsDbFS:db(rms),clippedSamples:clips,seamDelta:channels.map(c=>Math.abs(c[0]-c[c.length-1]))};
}

function normalize(channels, rmsTarget, peakLimit) {
  const before = metrics(channels);
  const gain = Math.min(rmsTarget / 10 ** (before.rmsDbFS / 20), peakLimit / 10 ** (before.peakDbFS / 20));
  for (const channel of channels) for (let i = 0; i < channel.length; i++) channel[i] *= gain;
  return metrics(channels);
}

function wav(channels) {
  const count = channels[0].length, dataLength = count * channels.length * 2;
  const bytes = Buffer.alloc(44 + dataLength);
  bytes.write('RIFF',0); bytes.writeUInt32LE(36+dataLength,4); bytes.write('WAVEfmt ',8);
  bytes.writeUInt32LE(16,16); bytes.writeUInt16LE(1,20); bytes.writeUInt16LE(channels.length,22);
  bytes.writeUInt32LE(rate,24); bytes.writeUInt32LE(rate*channels.length*2,28);
  bytes.writeUInt16LE(channels.length*2,32); bytes.writeUInt16LE(16,34); bytes.write('data',36); bytes.writeUInt32LE(dataLength,40);
  for (let i = 0; i < count; i++) for (let c = 0; c < channels.length; c++) bytes.writeInt16LE(Math.round(Math.max(-1,Math.min(1,channels[c][i]))*32767),44+(i*channels.length+c)*2);
  return bytes;
}

await mkdir(output,{recursive:true}); await mkdir(qa,{recursive:true});
const score = stereo(frames);
const chords = [
  {name:'Cmaj9',bass:36,notes:[55,59,62,64]}, {name:'Am7',bass:33,notes:[55,57,60,64]},
  {name:'Fmaj7',bass:29,notes:[53,57,60,64]}, {name:'Gsus2',bass:31,notes:[55,57,62,67]},
  {name:'Em7',bass:28,notes:[52,55,59,62]}, {name:'F6',bass:29,notes:[53,57,60,62]},
  {name:'Gadd9',bass:31,notes:[55,59,62,69]}
];
const melody = [
  [[.25,67],[2.5,72]],[[.75,76],[2.75,74]],[[.5,72],[3,69]],[[1.5,67]],
  [[0,69],[2.25,72]],[[.75,76],[3,72]],[[.5,74],[2.5,69]],[[1,67]],
  [[.25,71],[2.5,74]],[[1,76]],[[.5,72],[2.75,69]],[[1.25,67]],[[.25,69],[2.25,71]],[[.75,74],[2.75,67]],
  [[.5,76],[2.75,72]],[[1.25,79]],[[.25,76],[2.25,72]],[[1,69]],
  [[.25,72],[2.5,69]],[[1.25,67]],[[.5,74],[2.75,69]],[[1,67]],
  [[0,71],[2.25,74]],[[1.25,76]],[[.5,72],[3,69]],[[1.25,65]],[[.25,67],[2,69]],[[.5,71],[2.75,74]]
];
const events = [];
for (let phrase = 0; phrase < 14; phrase++) {
  const chord = chords[phrase % chords.length], start = phrase * 8;
  chord.notes.forEach((note,i)=>addNote(score,start+i*.035,note,10.4,.014,'strings',[-.38,.26,-.12,.4][i]));
  addNote(score,start+.04,chord.bass,6.5,.024,'bass',-.05);
  if (phrase % 2 === 0) addNote(score,start+5.15,chord.notes[1]+12,2.8,.017,'harp',.48);
  events.push({type:'harmony',at:start,chord:chord.name,bass:chord.bass,notes:chord.notes});
}
melody.forEach((bar,index)=>bar.forEach(([beat,note],at)=>{
  const start=index*4+beat+(random()-.5)*.055, gain=.043+(random()-.5)*.008;
  const timbre=(index+at)%4===2?'harp':'felt';
  addNote(score,start,note,3.8,gain,timbre,(random()-.5)*.28);
  events.push({type:timbre,bar:index+1,at:Number(start.toFixed(4)),note,gain:Number(gain.toFixed(5))});
}));
const music = room(score), musicMetrics = normalize(music,.05,.25);

// A separate, non-pitched leaf-air bed: deterministic filtered noise, not a
// continuous oscillator and not noise baked into the musical composition.
const airFrames=32*rate, noise=stereo(airFrames), air=stereo(airFrames);
for(let c=0;c<2;c++)for(let i=0;i<airFrames;i++)noise[c][i]=random()*2-1;
for(let c=0;c<2;c++){
  let fast=0,slow=0,soft=0;
  for(let cycle=0;cycle<2;cycle++)for(let i=0;i<airFrames;i++){
    fast+=.12*(noise[c][i]-fast); slow+=.018*(fast-slow); soft+=.08*((fast-slow)-soft);
    if(cycle===1){const t=i/airFrames;air[c][i]=soft*(.65+.17*Math.sin(t*Math.PI*2)+.08*Math.sin(t*Math.PI*6+.4));}
  }
}
const airMetrics=normalize(air,.014,.07);
const effects={};
function effect(name,seconds,make,peak){
  const sound=stereo(Math.ceil(seconds*rate));make(sound);const before=metrics(sound);
  const gain=peak/10**(before.peakDbFS/20);
  sound.forEach(c=>{for(let i=0;i<c.length;i++)c[i]*=gain;});effects[name]=sound;return metrics(sound);
}
const effectMetrics={};
effectMetrics['soft-step']=effect('soft-step',.13,s=>{
  let a=0,b=0;for(let i=0;i<s[0].length;i++){const t=i/rate;a+=.17*((random()*2-1)-a);b+=.04*(a-b);const x=(a-b)*smooth(t/.008)*Math.exp(-t/.027)*smooth((.13-t)/.035);s[0][i]=x;s[1][i]=x*.95;}
},.07);
effectMetrics['leaf-tap']=effect('leaf-tap',.18,s=>addNote(s,0,76,.18,.08,'harp'),.10);
effectMetrics['leaf-turn']=effect('leaf-turn',.40,s=>{addNote(s,0,67,.30,.06,'harp',-.1);addNote(s,.055,72,.30,.045,'harp',.1);},.11);
effectMetrics['leaf-rise']=effect('leaf-rise',.44,s=>{addNote(s,0,69,.30,.05,'harp',-.1);addNote(s,.075,76,.30,.05,'harp',.1);},.11);
effectMetrics['leaf-rest']=effect('leaf-rest',.25,s=>addNote(s,0,60,.25,.06,'harp'),.08);
effectMetrics['soft-latch']=effect('soft-latch',.30,s=>{addNote(s,0,55,.22,.08,'harp');addNote(s,.08,67,.20,.045,'harp');},.11);
effectMetrics['soft-grow']=effect('soft-grow',.65,s=>{addNote(s,0,60,.50,.05,'felt',-.1);addNote(s,.08,67,.50,.045,'harp',.1);},.11);
effectMetrics['soft-collect']=effect('soft-collect',.65,s=>{addNote(s,0,72,.55,.055,'felt',-.1);addNote(s,.08,79,.50,.035,'harp',.1);},.12);
effectMetrics['soft-complete']=effect('soft-complete',1.5,s=>{[60,64,67,72].forEach((n,i)=>addNote(s,i*.12,n,1.0,.045,'felt',(i-1.5)*.12));},.15);
effectMetrics['soft-chime']=effect('soft-chime',.70,s=>{addNote(s,0,72,.65,.05,'felt');addNote(s,.03,79,.60,.02,'felt',.2);},.10);
for(const [name,sound]of Object.entries(effects))await writeFile(join(output,name+'.wav'),wav(sound));
const musicMaster=join(qa,'garden-dawn-master.wav'),airMaster=join(qa,'garden-air-master.wav');
await writeFile(musicMaster,wav(music));await writeFile(airMaster,wav(air));
await writeFile(join(qa,'music-preview.wav'),wav(music.map(c=>c.slice(0,rate*32))));
const mix=stereo(rate*32);
for(let c=0;c<2;c++)for(let i=0;i<mix[c].length;i++)mix[c][i]=music[c][i]*.35+air[c][i%airFrames]*.25*.65;
const previewCues=[['soft-step',5,.4],['soft-step',5.6,.4],['leaf-tap',9,.34],['leaf-turn',12,.48],['leaf-rise',16,.48],['leaf-rest',20,.34],['soft-collect',25,.52],['soft-complete',29,.58]];
for(const [name,seconds,gain]of previewCues)for(let c=0;c<2;c++)for(let i=0;i<effects[name][c].length;i++){const at=Math.round(seconds*rate)+i;if(at<mix[c].length)mix[c][at]+=effects[name][c][i]*.6*gain;}
await writeFile(join(qa,'mix-preview.wav'),wav(mix));

// libsndfile/Vorbis needs more stack on this Windows Python runtime. Stream
// short blocks in an isolated worker rather than allocating a whole encode.
const encodeScript=`import sys,json,os,threading
import numpy as np
if sys.argv[1]: sys.path.insert(0,sys.argv[1])
import soundfile as sf
assert sf.check_format('OGG','VORBIS'), sf.available_subtypes('OGG')
results=[]
errors=[]
def encode():
 try:
  for src,dst in [(sys.argv[2],sys.argv[3]),(sys.argv[4],sys.argv[5])]:
   with sf.SoundFile(src) as source:
    rate,channels,frames=source.samplerate,source.channels,len(source)
    with sf.SoundFile(dst,'w',samplerate=rate,channels=channels,format='OGG',subtype='VORBIS') as target:
     while True:
      block=source.read(8192,dtype='float32',always_2d=True)
      if not len(block): break
      target.write(block)
   peak=0.0
   with sf.SoundFile(dst) as decoded:
    assert decoded.samplerate==rate and decoded.channels==channels and len(decoded)==frames
    while True:
     block=decoded.read(8192,dtype='float32',always_2d=True)
     if not len(block): break
     peak=max(peak,float(np.max(np.abs(block))))
   results.append({'file':os.path.basename(dst),'frames':frames,'channels':channels,'sampleRate':rate,'duration':frames/rate,'bytes':os.path.getsize(dst),'decodedPeakDbFS':float(20*np.log10(max(peak,1e-12)))})
 except Exception as error:
  errors.append(str(error))
threading.stack_size(16*1024*1024)
worker=threading.Thread(target=encode)
worker.start();worker.join()
if errors: raise RuntimeError(errors)
print(json.dumps({'soundfile':sf.__version__,'libsndfile':sf.__libsndfile_version__,'format':'OGG/VORBIS','files':results}))
`;
let encoded=null;
const encodedFiles=['garden-dawn.ogg','garden-air.ogg'];
try{
  encoded=await new Promise((done,reject)=>{const child=spawn(python,['-c',encodeScript,codec,musicMaster,join(output,encodedFiles[0]),airMaster,join(output,encodedFiles[1])],{windowsHide:true,stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);child.once('error',reject);child.once('close',code=>code===0?done(JSON.parse(stdout)):reject(Error(stderr||'codec exit '+code)));});
}catch(error){
  console.error('Vorbis codec unavailable; retaining independently named WAV runtime tracks: '+error.message);
  encodedFiles.splice(0,2,'garden-dawn.wav','garden-air.wav');
  await writeFile(join(output,encodedFiles[0]),wav(music));await writeFile(join(output,encodedFiles[1]),wav(air));
}
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=[];
for(const name of [...encodedFiles,...Object.keys(effects).map(n=>n+'.wav')]){const bytes=await readFile(join(output,name));files.push({file:name,bytes:bytes.length,sha256:digest(bytes)});}
const manifest={format:'sporelight.original-garden-score',version:1,title:'苔光间的慢舞 / A Quiet Dance in Mosslight',author:'Original local deterministic composition for Sporelight',source:'tools/godot-migration/compose-garden-music.mjs',sourceSha256:digest(await readFile(fileURLToPath(import.meta.url))),seed,sampleRate:rate,channels:2,tempoBpm:60,timeSignature:'4/4',bars:28,duration,composition:'Two related 14-bar phrases, seven two-bar harmonies, sparse felt keys and plucked strings, changing warm low harmony; no vocals or recorded samples.',loop:'Note releases and room taps wrap across the full 112-second period. Separate periodic filtered-noise air; no rain or ambience baked into the music.',assets:{music:encodedFiles[0],ambient:encodedFiles[1]},codec:encoded,musicMetrics,airMetrics,effectMetrics,previewMixMetrics:metrics(mix),previewSettings:{bgm:.35,ambient:.25,sfx:.6,ambientTrim:.65},events,files,externalSamples:false,auditioned:false};
await writeFile(join(output,'garden-score.json'),JSON.stringify(manifest,null,2)+'\n');
await writeFile(join(qa,'composition-report.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({title:manifest.title,duration,files:files.length,runtimeBytes:files.reduce((sum,f)=>sum+f.bytes,0),musicMetrics,airMetrics,codec:encoded?.format??'PCM WAV fallback',qa}));
