import {materialIcon} from '../ui';
import type {AppState} from '../types';
import {CHAPTERS,getLevel,LEVELS} from '../game/levels';
export function renderGameScene(state:AppState){
 const level=getLevel(state.save.lastLevel);const chapter=CHAPTERS.find(c=>c.id===level.chapter)!;
 const chapterLevels=LEVELS.filter(l=>l.chapter===chapter.id);
 return `<div class="screen journey-game grid-game ${level.chapter}">
  <canvas id="gameCanvas" width="1280" height="720" aria-label="${level.title}，等距石砖格子场景"></canvas>
  <div id="gridControls" class="grid-tile-controls" aria-label="可行走的石砖格子"></div>
  <header class="grid-level-card">${materialIcon('leaf')}<h1>${chapter.title}</h1><p>关卡 ${level.id} · ${level.title}</p></header>
  <div class="grid-chapter-dots" aria-label="章节进度">${chapterLevels.map(l=>`<i class="${state.save.levels[l.id].completed?'is-done':''} ${l.id===level.id?'is-current':''}"></i>`).join('')}</div>
  <aside class="grid-resource-card"><span>收集孢子</span><div>${materialIcon('spore')}<b id="sporeCount">0</b></div></aside>
  ${level.nodes.some(n=>n.mechanism)?`<div class="grid-life-purse">${materialIcon('leaf')}<b id="grownCount">0</b><small>唤醒</small></div>`:''}
  <nav class="grid-corner-controls"><button class="j-back" data-action="设置" aria-label="暂停与设置">${materialIcon('pause')}</button><button class="j-back" data-action="设置" aria-label="画面与声音设置">${materialIcon('settings')}</button></nav>
  <section id="puzzlePanel" class="puzzle-panel grid-puzzle-panel" aria-label="机关选择"></section>
  <p id="gameTip" class="grid-live-tip" role="status" aria-live="polite">方向键 / WASD 一步一格，空格或 J 跳跃。也可以点击石砖，逐格前往。</p>
  <nav class="grid-direction-pad" aria-label="方向控制"><button data-grid-direction="up" aria-label="向前一格" title="↑ / W">↑</button><button data-grid-direction="left" aria-label="向左一格" title="← / A">←</button><button class="grid-pad-jump" data-action="跳跃" aria-label="方向盘跳跃">⤴</button><button data-grid-direction="right" aria-label="向右一格" title="→ / D">→</button><button data-grid-direction="down" aria-label="向后一格" title="↓ / S">↓</button></nav>
  <div class="journey-game-bottom"><nav class="journey-toolbar" aria-label="游戏操作"><button data-action="返回关卡选择" aria-label="返回地图">${materialIcon('back')}<span>返回</span></button><button data-action="撤销" disabled>${materialIcon('undo')}<span>退回一格</span></button><button data-action="切换移动" aria-pressed="false" aria-label="切换为滚动">${materialIcon('roll','movement-normal')}${materialIcon('roll-active','movement-active')}<span>行走</span></button><button class="sow-action" data-action="播种">${materialIcon('sow','sow-normal')}${materialIcon('sow-active','sow-active')}<span data-action-label>播种 / 互动</span></button><button class="grid-jump-button" data-action="跳跃" aria-label="跳跃" aria-keyshortcuts="Space J"><img class="material-icon" src="/images/material-ready/jump.png" alt=""/><span>跳跃</span></button><button data-action="提示">${materialIcon('hint')}<span>提示</span></button><button data-action="重来">${materialIcon('retry')}<span>重来</span></button></nav><small class="game-key-guide">方向键 / WASD：一格　·　空格 / J：跳跃　·　E：互动　·　1–4：机关选择</small></div>
 </div>`;
}
