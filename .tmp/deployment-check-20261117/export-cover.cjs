const fs=require('node:fs/promises');
const sharp=require('C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1112-737-0_26.1112.737.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules/sharp');
const path=require('node:path');
(async()=>{
 const source='C:/Users/liuli/.codex/generated_images/01a1e88a-5313-72d2-8cbb-4b62fe70e606/exec-9bcf701c-4539-48a3-9baf-213d9ae0531f.png';
 const output=path.resolve('output/deployment-20261117');
 await fs.copyFile(source,path.join(output,'sporelight-cover-generated-original.png'));
 await sharp(source).resize(1920,1080,{fit:'cover',position:'centre'}).png().toFile(path.join(output,'sporelight-cover-1920x1080.png'));
 await sharp(source).resize(1920,1080,{fit:'cover',position:'centre'}).jpeg({quality:95,mozjpeg:true}).toFile(path.join(output,'sporelight-cover-1920x1080.jpg'));
 const image=sharp(source).resize(1920,1080,{fit:'cover',position:'centre',kernel:'lanczos3'});
 await image.clone().png().toFile(path.join(output,'sporelight-cover-1920x1080.png'));
 await image.clone().jpeg({quality:95,mozjpeg:true}).toFile(path.join(output,'sporelight-cover-1920x1080.jpg'));
 const meta=await sharp(path.join(output,'sporelight-cover-1920x1080.png')).metadata();
 if(meta.width!==1920||meta.height!==1080)throw Error('Wrong final cover size');
 console.log(JSON.stringify({original:await sharp(source).metadata(),final:meta}));
})();
