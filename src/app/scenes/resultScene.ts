import type { AppState } from '../types';
import { CHAPTERS, getLevel } from '../game/levels';
import { GALLERY_ITEMS } from './galleryScene';
import { sporeIcon } from './mapPresentation';
export function renderResultScene(state: AppState) {
  const level=getLevel(state.save.lastLevel);const result=state.result;const finale=level.id==='3-4';
  const chapter=CHAPTERS.find(c=>c.id===level.chapter)!;
  const totalAwakened=level.nodes.filter(n=>n.mechanism).length;
  // The terminal flower is also a life awakened by finishing the journey.
  const terminalAwakened=result?.completed?1:0;
  return `<div class="screen illustrated-result result-theme-${level.chapter}" style="background-image:url('./images/reference-scenes/result-${level.chapter}.jpg')"><div class="result-light-wash" aria-hidden="true"></div><section class="illustrated-result-copy"><h1>${finale?'微光苔原':chapter.title} <em>已唤醒</em></h1><p>${finale?'你走过的路，都亮起来了。':`${level.id} · ${level.title}`}</p><div class="illustrated-result-stats"><div><span>孢子收集：</span>${sporeIcon}<strong>${result?.collected??0}</strong><b>/ ${result?.total??0}</b></div><div><span>唤醒生命：</span><img src="./images/sporelight_complete_assets_png/ui/icons/ui_icon_leaf.png" alt=""/><strong>${(result?.awakened??0)+terminalAwakened}</strong><b>/ ${totalAwakened+1}</b></div></div><div class="illustrated-result-stars" aria-label="${result?.stars??1}枚星光">${'✦'.repeat(result?.stars??1)}<span>${'✧'.repeat(3-(result?.stars??1))}</span></div></section><nav class="illustrated-result-actions" aria-label="通关后的操作"><button data-action="${finale?'图鉴':'下一关'}"><span>${finale?'❧':'➜'}</span>${finale?'自然图鉴':'下一关'}</button><button data-action="重玩"><span>↶</span>重玩本关</button><button data-action="返回关卡选择"><span>♧</span>返回地图</button></nav><div class="illustrated-result-discovery">${finale?'谢谢你，陪露薇走过这一段微光。':`自然图鉴已记录 · ${level.rewards.map(id=>GALLERY_ITEMS.find(i=>i.id===id)?.title).join(' / ')}`}</div><div class="celebration-petals" aria-hidden="true">${Array.from({length:12},(_,i)=>`<i style="--x:${70+(i*107)%1140}px;--delay:${-i*1.3}s;--duration:${9+i%5}s"></i>`).join('')}</div></div>`;
}
