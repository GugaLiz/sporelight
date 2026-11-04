import {readdir,readFile} from 'node:fs/promises';
import {join,relative,sep} from 'node:path';
import {createHash} from 'node:crypto';

export async function sourceDigest(root){
 const folder=join(root,'godot');
 const entries=[];
 async function visit(path){
  for(const item of await readdir(path,{withFileTypes:true})){
   if(item.isDirectory()){
    if(!['.godot','build','tests'].includes(item.name))await visit(join(path,item.name));
   }else if(!['README.md'].includes(item.name)){
    const file=join(path,item.name);
    entries.push([relative(folder,file).split(sep).join('/'),createHash('sha256').update(await readFile(file)).digest('hex')]);
   }
  }
 }
 await visit(folder);
 entries.sort(([a],[b])=>a.localeCompare(b,'en'));
 return {sha256:createHash('sha256').update(JSON.stringify(entries)).digest('hex'),files:entries.length};
}

