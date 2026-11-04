import https from 'node:https';
import {createHash} from 'node:crypto';
import {createWriteStream,createReadStream} from 'node:fs';
import {mkdir,readFile,writeFile,stat,access} from 'node:fs/promises';
import {pipeline} from 'node:stream/promises';
import {inflateRawSync} from 'node:zlib';
import {spawn} from 'node:child_process';
import {resolve,dirname,join,basename} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const lock=JSON.parse(await readFile(join(root,'godot/toolchain.json'),'utf8'));
if(process.platform!=='win32')throw Error('This pinned bootstrap installs the official Windows editor. Other hosts must provide GODOT_BIN.');
const cache=join(process.env.USERPROFILE,'.cache/sporelight-godot/4.7.2');
await mkdir(cache,{recursive:true});
const agent=new https.Agent({keepAlive:true,maxSockets:5});
function request(url,headers={},redirects=0){
 return new Promise((done,reject)=>{
  const req=https.get(url,{agent,headers:{'User-Agent':'Sporelight-Godot-Migration','Accept-Encoding':'identity',...headers}},res=>{
   if([301,302,303,307,308].includes(res.statusCode)&&res.headers.location){
    res.resume();
    if(redirects>6){reject(Error('Too many official download redirects'));return;}
    done(request(new URL(res.headers.location,url),headers,redirects+1));return;
   }
   done(res);
  });
  req.setTimeout(25000,()=>req.destroy(Error('Official transfer stalled')));
  req.on('error',reject);
 });
}
async function assetURL(id){
 const res=await request('https://api.github.com/repos/'+lock.editorAsset.repository+'/releases/assets/'+id+'?download=1',{Accept:'application/octet-stream'});
 if(res.statusCode!==200){res.resume();throw Error('Official asset returned HTTP '+res.statusCode);}
 return res;
}
async function hashFile(file){
 const hash=createHash('sha256');
 for await(const chunk of createReadStream(file))hash.update(chunk);
 return hash.digest('hex');
}
const editorArchive=join(cache,lock.editorAsset.name);
let engineValid=false;
try{engineValid=(await stat(editorArchive)).size===lock.editorAsset.size&&(await hashFile(editorArchive))===lock.editorAsset.sha256;}catch{}
if(!engineValid){
 console.log('Downloading pinned official Godot editor...');
 const response=await assetURL(lock.editorAsset.assetId);
 const pending=editorArchive+'.download';
 await pipeline(response,createWriteStream(pending));
 if((await stat(pending)).size!==lock.editorAsset.size||(await hashFile(pending))!==lock.editorAsset.sha256)throw Error('Editor SHA256 or length differs from the official lock.');
 await writeFile(editorArchive,await readFile(pending));
}
const engineDirectory=join(cache,'engine');
await mkdir(engineDirectory,{recursive:true});
const executable=join(engineDirectory,'Godot_v4.7.2-stable_win64_console.exe');
try{await access(executable);}catch{
 await new Promise((done,reject)=>{
  const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-Command','Expand-Archive -LiteralPath $env:SPORELIGHT_GODOT_ARCHIVE -DestinationPath $env:SPORELIGHT_GODOT_ENGINE -Force'],{windowsHide:true,stdio:'inherit',env:{...process.env,SPORELIGHT_GODOT_ARCHIVE:editorArchive,SPORELIGHT_GODOT_ENGINE:engineDirectory}});
  child.on('error',reject);child.on('close',code=>code===0?done():reject(Error('Official editor extraction failed')));
 });
}
// Extract just the Web/Windows template entries from the official ZIP using HTTP ranges.
// Range data is checked against the official ZIP directory CRC32 and length.
// This does not claim verification of the complete 1.28 GB archive SHA256.
async function templateRange(start,end,file){
 try{const existing=await readFile(file);if(existing.length===end-start+1)return existing;}catch{}
 const res=await request('https://api.github.com/repos/'+lock.editorAsset.repository+'/releases/assets/'+lock.templateAsset.assetId+'?download=1',{Accept:'application/octet-stream',Range:'bytes='+start+'-'+end});
 const expected='bytes '+start+'-'+end+'/'+lock.templateAsset.size;
 if(res.statusCode!==206||res.headers['content-range']!==expected){res.resume();throw Error('Official template server did not honor the exact range.');}
 const chunks=[];for await(const chunk of res)chunks.push(chunk);
 const bytes=Buffer.concat(chunks);
 if(bytes.length!==end-start+1)throw Error('Truncated template range');
 await writeFile(file,bytes);return bytes;
}
const tailStart=lock.templateAsset.size-65536;
const tail=await templateRange(tailStart,lock.templateAsset.size-1,join(cache,'templates-tail.bin'));
let end=-1;
for(let i=tail.length-22;i>=0;i--){if(tail.readUInt32LE(i)===0x06054b50){end=i;break;}}
if(end<0)throw Error('Official ZIP central directory not found');
const centralSize=tail.readUInt32LE(end+12),centralOffset=tail.readUInt32LE(end+16);
const central=centralOffset>=tailStart?tail.subarray(centralOffset-tailStart,centralOffset-tailStart+centralSize):await templateRange(centralOffset,centralOffset+centralSize-1,join(cache,'bootstrap-central.bin'));
const entries=[];
for(let cursor=0;cursor<central.length;){
 if(central.readUInt32LE(cursor)!==0x02014b50)throw Error('Invalid template central entry');
 const nameLength=central.readUInt16LE(cursor+28),extra=central.readUInt16LE(cursor+30),comment=central.readUInt16LE(cursor+32);
 entries.push({name:central.subarray(cursor+46,cursor+46+nameLength).toString(),method:central.readUInt16LE(cursor+10),crc:central.readUInt32LE(cursor+16),compressed:central.readUInt32LE(cursor+20),length:central.readUInt32LE(cursor+24),offset:central.readUInt32LE(cursor+42)});
 cursor+=46+nameLength+extra+comment;
}
const table=Array.from({length:256},(_,n)=>{for(let i=0;i<8;i++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
function crc(bytes){let value=0xffffffff;for(const b of bytes)value=table[(value^b)&255]^(value>>>8);return(value^0xffffffff)>>>0;}
const target=join(process.env.APPDATA,'Godot/export_templates/4.7.2.stable');
await mkdir(target,{recursive:true});
const wanted=['version.txt','icudt_godot.dat','web_nothreads_debug.zip','web_nothreads_release.zip','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe','windows_release_x86_64.exe','windows_release_x86_64_console.exe'];
const verified=[];
for(const name of wanted){
 const entry=entries.find(e=>basename(e.name)===name);if(!entry)throw Error('Required official template is missing: '+name);
 const destination=join(target,name);
 let current;try{current=await readFile(destination);}catch{}
 if(!current||current.length!==entry.length||crc(current)!==entry.crc){
  console.log('Installing official template '+name+'...');
  const header=await templateRange(entry.offset,entry.offset+255,join(cache,'bootstrap-header-'+name+'.bin'));
  if(header.readUInt32LE(0)!==0x04034b50)throw Error('Invalid local ZIP header');
  const start=entry.offset+30+header.readUInt16LE(26)+header.readUInt16LE(28);
  const parts=[];
  for(let off=0;off<entry.compressed;off+=1048576)parts.push({start:start+off,end:start+Math.min(entry.compressed,off+1048576)-1,file:join(cache,'bootstrap-'+name+'-'+off+'.bin')});
  let next=0;
  const data=new Array(parts.length);
  await Promise.all(Array.from({length:3},async()=>{while(next<parts.length){const index=next++,p=parts[index];data[index]=await templateRange(p.start,p.end,p.file);}}));
  const packed=Buffer.concat(data);current=entry.method===8?inflateRawSync(packed):packed;
  if(current.length!==entry.length||crc(current)!==entry.crc)throw Error('Template ZIP checksum mismatch: '+name);
  await writeFile(destination,current);
 }
 verified.push({name,bytes:entry.length,crc32:entry.crc,sha256:createHash('sha256').update(current).digest('hex')});
}
await writeFile(join(cache,'verified-toolchain.json'),JSON.stringify({editorSHA256:lock.editorAsset.sha256,templates:verified,fullTemplateArchiveSHA256Verified:false},null,2)+'\n');
console.log(JSON.stringify({engine:executable,templates:target,verified:verified.length}));
