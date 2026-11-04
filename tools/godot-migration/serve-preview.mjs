import http from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {resolve,dirname,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const projectRoot=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(value=>value.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const variant=option('variant',process.env.GODOT_PREVIEW_VARIANT??'web');
if(!['web','web-release'].includes(variant))throw Error('Unknown preview variant');
const directory=resolve(projectRoot,'godot/build',variant);
const port=Number(option('port',process.env.GODOT_PREVIEW_PORT??4185));
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'};
const server=http.createServer(async(request,response)=>{
 try{
  const url=new URL(request.url??'/', 'http://localhost');
  if(url.pathname==='/favicon.ico'){response.writeHead(204).end();return;}
  if(url.pathname==='/__build.json'){
   const data=await readFile(resolve(directory,'build.json')).catch(error=>{if(error.code!=='ENOENT')throw error;return readFile(resolve(projectRoot,'godot/build/build.json'));});
   response.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'}).end(data);return;
  }
  const relative=decodeURIComponent(url.pathname).replace(/^\/+/,'')||'index.html';
  const file=resolve(directory,relative);
  if(file!==directory&&!file.startsWith(directory+sep)){response.writeHead(403).end();return;}
  const info=await stat(file);
  if(!info.isFile()){response.writeHead(404).end();return;}
  response.writeHead(200,{'Content-Type':types[extname(file)]??'application/octet-stream','Content-Length':info.size,'Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp'});
  response.end(await readFile(file));
 }catch(error){response.writeHead(error.code==='ENOENT'?404:500).end();}
});
server.on('error',error=>{console.error(error.message);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>console.log('Godot '+variant+' preview: http://localhost:'+port+'/'));
