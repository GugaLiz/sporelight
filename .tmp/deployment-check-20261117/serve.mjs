import http from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
const root=resolve('dist');
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml','.ico':'image/x-icon','.json':'application/json','.webmanifest':'application/manifest+json'};
http.createServer(async(req,res)=>{try{let path=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(path.startsWith('/sporelight/'))path=path.slice('/sporelight'.length);if(path.endsWith('/'))path+='index.html';const file=resolve(root,'.'+path);if(!file.startsWith(root+sep))throw Error('Forbidden');if(!(await stat(file)).isFile())throw Error('Not file');const bytes=await readFile(file);res.writeHead(200,{'Content-Type':types[extname(file)]??'application/octet-stream','Content-Length':bytes.length,'Cache-Control':'no-cache'});res.end(bytes);}catch{res.writeHead(404).end('Not found');}}).listen(4224,'127.0.0.1',()=>console.log('Plain static dist preview: http://localhost:4224/sporelight/ (no COOP/COEP headers)'));
