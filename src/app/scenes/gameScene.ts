import type { AppState } from '../types';
import { CHAPTERS, getLevel, mechanismName } from '../game/levels';
export function renderGameScene(state: AppState) {
  const level = getLevel(state.save.lastLevel); const chapter = CHAPTERS.find(c => c.id === level.chapter)!;
  return `<div class="screen journey-game ${level.chapter}"><canvas id="gameCanvas" width="1280" height="720" aria-label="${level.title}游戏场景"></canvas>
    <header class="journey-game-header"><button class="j-back" data-action="返回关卡选择" aria-label="返回地图">←</button><div><span class="eyebrow">${chapter.title} · ${level.id}</span><h1>${level.title}</h1></div><div class="game-counters"><span>✦ <b id="sporeCount">0</b><small>孢子</small></span><span>❧ <b id="grownCount">0</b><small>唤醒</small></span></div><button class="j-back" data-action="设置" aria-label="暂停与设置">Ⅱ</button></header>
    <p class="game-objective">${level.subtitle}</p>
    <div class="node-controls" aria-label="可交互的石台">${level.nodes.map(node => `<button class="node-hit" data-node="${node.id}" style="left:${node.x - 48}px;top:${node.y - 108}px" aria-label="移动到${node.mechanism ? mechanismName[node.mechanism] : '石台'}"><span class="node-focus-ring"></span></button>`).join('')}</div>
    <div class="journey-game-bottom"><p id="gameTip" role="status" aria-live="polite">点击石台移动，点击脚下的植物或按 E 播种。</p><nav class="journey-toolbar" aria-label="游戏操作"><button data-action="撤销" disabled>↶ <span>退回一步</span></button><button data-action="重来">↻ <span>重新开始</span></button><button class="sow-action" data-action="播种">✧ 播种 / 互动 · E</button><button data-action="提示">☼ <span>一点提示</span></button><button data-action="设置">Ⅱ <span>休息一下</span></button></nav><small class="game-key-guide">点击石台 / 方向键移动　·　E 互动　·　Esc 暂停</small></div>
  </div>`;
}
