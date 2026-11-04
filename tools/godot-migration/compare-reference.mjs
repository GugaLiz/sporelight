import {readFile} from 'node:fs/promises';

const [expectedPath,actualPath]=process.argv.slice(2);
if(!expectedPath||!actualPath){console.error('Usage: node compare-reference.mjs reference.json actual.json');process.exit(2);}
const expected=JSON.parse(await readFile(expectedPath,'utf8'));
const actual=JSON.parse(await readFile(actualPath,'utf8'));
function normalize(value,key=''){
 if(key==='trial'&&typeof value==='string'){try{return normalize(JSON.parse(value));}catch{return value;}}
 if(Array.isArray(value))return value.map(v=>normalize(v));
 if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,normalize(value[k],k)]));
 return Object.is(value,-0)?0:value;
}
function firstDiff(a,b,path='$'){
 if(typeof a!==typeof b||a===null||b===null){return a===b?null:{path,expected:a,actual:b};}
 if(Array.isArray(a)||Array.isArray(b)){if(!Array.isArray(a)||!Array.isArray(b)||a.length!==b.length)return {path:`${path}.length`,expected:a?.length,actual:b?.length};for(let i=0;i<a.length;i++){const d=firstDiff(a[i],b[i],`${path}[${i}]`);if(d)return d;}return null;}
 if(typeof a==='object'){const keys=[...new Set([...Object.keys(a),...Object.keys(b)])].sort();for(const k of keys){if(!(k in a)||!(k in b))return {path:`${path}.${k}`,expected:a[k],actual:b[k]};const d=firstDiff(a[k],b[k],`${path}.${k}`);if(d)return d;}return null;}
 return a===b?null:{path,expected:a,actual:b};
}
const diff=firstDiff(normalize(expected.cases??expected),normalize(actual.cases??actual));
if(diff){console.error(JSON.stringify(diff,null,2));process.exitCode=1;}else console.log(JSON.stringify({equal:true,cases:expected.cases?.length??null}));
