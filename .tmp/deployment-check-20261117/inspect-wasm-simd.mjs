import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const bytes=await readFile('dist/index.wasm');
let p=8;
const uleb=()=>{let value=0,shift=0,byte;do{byte=bytes[p++];value+=(byte&127)*2**shift;shift+=7;}while(byte&128);return value;};
const evidence={sha256:createHash('sha256').update(bytes).digest('hex'),wasmBytes:bytes.length,functionTypes:0,v128Parameters:0,v128Results:0,functions:0,functionsWithV128Locals:0,v128LocalGroups:0};
while(p<bytes.length){
 const section=bytes[p++],size=uleb(),end=p+size;
 if(section===1){const count=uleb();evidence.functionTypes=count;for(let i=0;i<count;i++){if(bytes[p++]!==0x60)throw Error('Unexpected non-function type');for(const field of ['v128Parameters','v128Results']){const len=uleb();for(let j=0;j<len;j++)if(bytes[p++]===0x7b)evidence[field]++;}}}
 if(section===10){const count=uleb();evidence.functions=count;for(let i=0;i<count;i++){const len=uleb(),bodyEnd=p+len,groups=uleb();let found=false;for(let j=0;j<groups;j++){uleb();if(bytes[p++]===0x7b){evidence.v128LocalGroups++;found=true;}}if(found)evidence.functionsWithV128Locals++;p=bodyEnd;}}
 p=end;
}
const probe=new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11]);
evidence.simdProbeValidInNode=WebAssembly.validate(probe);
evidence.requiresSIMD=evidence.v128Parameters+evidence.v128Results+evidence.v128LocalGroups>0;
await writeFile('output/deployment-20261117/wasm-simd-evidence.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence,null,2));
