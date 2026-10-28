import type {AppState,SaveData} from '../types';
import {escapeHtml,materialIcon} from '../ui';
import {sporeIcon} from './mapPresentation';
import {GALLERY_ITEMS,GALLERY_CATEGORIES,gallerySelection,galleryUnlocked,galleryMarks,galleryFirstFound,galleryHint,type GalleryItem,type GalleryMode} from './galleryData';
export {GALLERY_ITEMS} from './galleryData';

function marks(value:number){return `<div class="journal-marks" role="img" aria-label="观察印记 ${value} / 5" title="关联关卡收集得越完整，观察印记越明亮">${Array.from({length:5},(_,i)=>`<span class="${i<value?'is-lit':''}" aria-hidden="true">★</span>`).join('')}</div>`;}
export function renderGalleryDetail(item:GalleryItem|null,save:SaveData,mode:GalleryMode='entry'){
 if(!item)return `<div class="journal-detail-empty"><span>❧</span><h2>这一页，留给新的相遇。</h2><p>选择另一个分类，继续翻阅微光。</p></div>`;
 const unlocked=galleryUnlocked(save,item);const title=escapeHtml(item.title);
 if(!unlocked)return `<article class="journal-detail-content journal-undiscovered"><h2 class="detail-title">${title}</h2>${marks(0)}<div class="journal-detail-art journal-silhouette"><img src="${item.image}" alt="${title}的未发现剪影"/></div><h3>尚未发现</h3><p>这一页还没有被微光写满。<br>${escapeHtml(galleryHint(item))}</p><div class="journal-detail-divider">✧</div><small>初次相遇后，便能读到它的故事。</small><button class="journal-journey-button" data-action="返回关卡选择">循着微光去寻找 →</button></article>`;
 if(mode==='story')return `<article class="journal-detail-content journal-story-content"><span class="journal-story-kicker">一页自然的小故事</span><h2 class="detail-title">${title}</h2><div class="journal-story-art"><img src="${item.image}" alt="${title}"/></div><div class="journal-story-prose">${item.story.map(paragraph=>`<p>${escapeHtml(paragraph.split('{name}').join(save.playerName))}</p>`).join('')}</div><blockquote>${escapeHtml(item.poem)}</blockquote><div class="journal-story-signature">记于 · ${escapeHtml(galleryFirstFound(save,item))}</div></article>`;
 return `<article class="journal-detail-content"><h2 class="detail-title">${title}</h2>${marks(galleryMarks(save,item))}<div class="journal-detail-art"><img src="${item.image}" alt="${title}"/></div><p class="journal-detail-desc">${escapeHtml(item.desc)}</p><div class="journal-detail-divider">✧</div><dl class="journal-detail-meta"><div><dt>❧　栖息环境</dt><dd>${escapeHtml(item.habitat)}</dd></div><div><dt>▧　首次发现</dt><dd>${escapeHtml(galleryFirstFound(save,item))}</dd></div></dl></article>`;
}
export function renderGalleryScene(state:AppState){
 const {category,items,selected,mode}=gallerySelection(state);
 const found=GALLERY_ITEMS.filter(item=>galleryUnlocked(state.save,item)).length;
 const icons:Record<string,string>={'全部':'❧','植物':'♧','生物':'✧','建筑':'⌂','奇物':'◇'};
 return `<div class="screen illustrated-gallery" style="background-image:url('./images/gallery-journal/book-scene.jpg')">
 <button class="journal-back" data-action="返回主菜单" aria-label="返回主菜单"><span class="journal-sr-only">返回</span></button>
 <header class="journal-heading"><h1>图鉴 / 画册</h1><p>微光苔原 · Sporelight</p></header>
 <div class="journal-total" aria-label="已收集 ${found} / ${GALLERY_ITEMS.length}"><span>已收集</span>${sporeIcon}<b>${found}<i>/ ${GALLERY_ITEMS.length}</i></b></div>
 <nav class="journal-categories" role="tablist" aria-label="图鉴分类">${GALLERY_CATEGORIES.map(cat=>{const list=GALLERY_ITEMS.filter(i=>cat==='全部'||i.category===cat);const count=list.filter(i=>galleryUnlocked(state.save,i)).length;return `<button class="journal-category ${cat===category?'is-active':''}" role="tab" id="journal-category-${cat}" aria-selected="${cat===category}" aria-controls="galleryGrid" tabindex="${cat===category?0:-1}" data-gallery-cat="${cat}"><span aria-hidden="true">${icons[cat]}</span>${cat}<small>${count}/${list.length}</small></button>`;}).join('')}</nav>
 <section class="journal-card-grid" id="galleryGrid" role="tabpanel" aria-labelledby="journal-category-${category}" aria-label="图鉴卡片">${items.length?items.map(item=>{const unlocked=galleryUnlocked(state.save,item),chosen=selected?.id===item.id;return `<button class="gallery-card journal-card ${unlocked?'unlocked':'locked'} ${chosen?'is-selected':''}" data-gallery-id="${item.id}" data-category="${item.category}" aria-pressed="${chosen}" aria-label="${item.title}，${unlocked?'已发现':'未发现'}"><h2>${escapeHtml(item.title)}</h2><span class="journal-card-divider" aria-hidden="true">◇</span><div class="journal-card-art ${unlocked?'':'journal-silhouette'}"><img src="${item.image}" alt="${unlocked?item.title:'未发现的剪影'}"/></div>${unlocked?marks(galleryMarks(state.save,item)):'<span class="journal-unfound-label">未发现</span>'}</button>`;}).join(''):'<p class="journal-grid-empty">暂时没有这一类相遇，翻到别的书页看看吧。</p>'}</section>
 <aside class="journal-detail-sheet" id="galleryDetail" role="tabpanel" aria-label="${mode==='entry'?'图鉴详情':'自然故事'}" aria-labelledby="journal-mode-${mode}"><button class="journal-return-list" data-gallery-list>↑ 回到画册</button>${renderGalleryDetail(selected,state.save,mode)}</aside>
 <nav class="journal-side-tabs" role="tablist" aria-label="详情页签"><button id="journal-mode-entry" role="tab" aria-selected="${mode==='entry'}" aria-controls="galleryDetail" tabindex="${mode==='entry'?0:-1}" data-gallery-mode="entry" class="${mode==='entry'?'is-active':''}">${materialIcon('leaf')}<span>图鉴</span></button><button id="journal-mode-story" role="tab" aria-selected="${mode==='story'}" aria-controls="galleryDetail" tabindex="${mode==='story'?0:-1}" data-gallery-mode="story" class="${mode==='story'?'is-active':''}">${materialIcon('gallery')}<span>故事</span></button></nav>
 <img class="journal-reading-companion" src="./images/gallery-journal/reading-companion.png" alt="露薇陪你翻阅自然画册"/>
 <div class="journal-page-number" aria-hidden="true">${selected?`${String(GALLERY_ITEMS.indexOf(selected)+1).padStart(2,'0')} / ${String(GALLERY_ITEMS.length).padStart(2,'0')}`:'—'}</div>
 </div>`;
}
