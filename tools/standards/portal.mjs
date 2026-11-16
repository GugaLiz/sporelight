import {readFile,stat} from 'node:fs/promises';
import {resolve,sep,extname} from 'node:path';

export const STANDARDS_PATH='/__standards/';
const documents=[
 ['overview','公共元素库与复用契约','docs/106-前三章公共游戏元素库与复用契约.md'],
 ['actors','角色与蘑菇伙伴','docs/element-library/actors.md'],
 ['props','花坛、道具与布景','docs/element-library/props.md'],
 ['surfaces','地板、墙面与道路','docs/element-library/surfaces.md'],
 ['catalog','目录与编辑器契约','docs/element-library/catalog.md'],
 ['quality','基础质量规则与问题台账','docs/69-游戏开发基础质量规则与问题台账.md'],
 ['scene-contract','视觉与空间合同','.agents/skills/game-scene-quality/references/scene-contract.md'],
 ['project-adapter','Sporelight 项目约定','.agents/skills/game-scene-quality/references/sporelight.md'],
];
const contentTypes={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.svg':'image/svg+xml','.ico':'image/x-icon'};
const loopback=address=>['127.0.0.1','::1','::ffff:127.0.0.1'].includes(address);
export function isLocalRequest(request){
 try{
  const hostname=new URL('http://'+request.headers.host).hostname;
  const forwarded=Object.keys(request.headers).some(key=>key==='forwarded'||key.startsWith('x-forwarded-')||key==='x-real-ip');
  return ['localhost','127.0.0.1','[::1]'].includes(hostname)&&loopback(request.socket.remoteAddress)&&!forwarded;
 }catch{return false;}
}

/** A preview-server capability, never copied into the exported game. */
export function createStandardsPortal({projectRoot,enabled=true}){
 const root=resolve(projectRoot),web=resolve(root,'tools/standards/web');
 let inventoryCache=null,inventoryStamp='';
 async function inventory(){
  const path=resolve(root,'docs/element-library/inventory.json'),info=await stat(path);
  const stamp=info.mtimeMs+':'+info.size;
  if(stamp!==inventoryStamp){inventoryCache=JSON.parse(await readFile(path,'utf8'));inventoryStamp=stamp;}
  return inventoryCache;
 }
 function send(request,response,status,body,type='text/plain; charset=utf-8'){
  const bytes=Buffer.isBuffer(body)?body:Buffer.from(body);
  response.writeHead(status,{'Content-Type':type,'Content-Length':bytes.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Cross-Origin-Resource-Policy':'same-origin','Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; base-uri 'none'; frame-ancestors 'none'"});
  response.end(request.method==='HEAD'?undefined:bytes);
 }
 return {
  inject(html,request){
   const pathname=new URL(request.url??'/','http://localhost').pathname;
   if(!enabled||!isLocalRequest(request)||pathname.startsWith('/__standards')||html.includes('data-sporelight-standards'))return html;
   return html.replace('</body>','<script data-sporelight-standards src="/__standards/entry.js" defer></script>\n</body>');
  },
  async handle(request,response){
   const url=new URL(request.url??'/','http://localhost');
   if(url.pathname!=='/__standards'&&!url.pathname.startsWith(STANDARDS_PATH))return false;
   if(!enabled||!isLocalRequest(request)){send(request,response,404,'Not found');return true;}
   if(!['GET','HEAD'].includes(request.method)){send(request,response,405,'Read-only handbook');return true;}
   try{
    if(url.pathname==='/__standards'){response.writeHead(302,{Location:STANDARDS_PATH,'Cache-Control':'no-store'}).end();return true;}
    const relative=decodeURIComponent(url.pathname.slice(STANDARDS_PATH.length));
    if(relative==='data.json'){
     const data=await inventory();
     const docs=await Promise.all(documents.map(async([id,title,path])=>({id,title,path,body:await readFile(resolve(root,path),'utf8')})));
     const assets=Object.fromEntries(Object.keys(data.definitions.resources).map(alias=>[alias,STANDARDS_PATH+'assets/'+encodeURIComponent(alias)]));
     send(request,response,200,JSON.stringify({inventory:data,documents:docs,assets}),'application/json; charset=utf-8');
    }else if(relative.startsWith('assets/')){
     const alias=relative.slice(7),data=await inventory(),resource=data.definitions.resources[alias];
     if(typeof resource!=='string'||!resource.startsWith('res://assets/')){send(request,response,404,'Unknown asset');return true;}
     const file=resolve(root,'godot',resource.slice(6)),assetRoot=resolve(root,'godot/assets');
     const type=contentTypes[extname(file).toLowerCase()];
     if(!file.startsWith(assetRoot+sep)||!type?.startsWith('image/')){send(request,response,404,'Unknown asset');return true;}
     send(request,response,200,await readFile(file),type);
    }else{
     const allowed={'':'index.html','index.html':'index.html','styles.css':'styles.css','app.js':'app.js','entry.js':'entry.js','entry.css':'entry.css'};
     if(!Object.hasOwn(allowed,relative)){send(request,response,404,'Not found');return true;}
     const file=resolve(web,allowed[relative]);
     send(request,response,200,await readFile(file),contentTypes[extname(file)]);
    }
   }catch(error){
    // Keep repository paths and private filesystem errors out of browser output.
    send(request,response,error.code==='ENOENT'?404:500,'无法读取本地手册，请检查文档文件后重试。');
   }
   return true;
  },
 };
}

/** Vite development only; no transform or files are added to production builds. */
export function localStandardsPlugin(projectRoot){
 const portal=createStandardsPortal({projectRoot});
 return {
  name:'sporelight-local-standards',apply:'serve',
  configureServer(server){
   server.middlewares.use((request,response,next)=>{
    // Capture the HTML response from Vite while preserving its request identity.
    // This keeps public-host requests free of the local launcher as well.
    const end=response.end;
    response.end=function(chunk,encoding,callback){
     if((typeof chunk==='string'||Buffer.isBuffer(chunk))&&String(response.getHeader('Content-Type')).includes('text/html')){
      chunk=Buffer.from(portal.inject(chunk.toString(),request));
      response.setHeader('Content-Length',chunk.length);
     }
     return end.call(this,chunk,encoding,callback);
    };
    portal.handle(request,response).then(handled=>{if(!handled)next();}).catch(next);
   });
  },
 };
}
