import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState, LevelId } from '../types';

const COMPLETE = COMPLETE_ASSET_ROOT;

const LEVELS: ReadonlyArray<{ id: LevelId; title: string; desc: string; bg: string }> = [
  { id: 'valley', title: '1-1 苔藓山谷', desc: '播下微光，让苔藓重新连成小路。', bg: 'bg_valley.png' },
  { id: 'pond', title: '1-2 雨滴池塘', desc: '睡莲还在等待下一阵雨。', bg: 'bg_pond.png' },
  { id: 'cave', title: '1-3 星光洞穴', desc: '洞穴深处的星光仍未醒来。', bg: 'bg_cave.png' }
];

export function renderLevelSelectScene(state: AppState) {
  return `
    <div class="screen level-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_level_select.png`)}')">
      <button class="round-nav back" data-action="返回主菜单">返回</button>
      <button class="round-nav settings" data-action="设置">设置</button>
      <h1>选择旅程</h1>

      <div class="level-grid">
        ${LEVELS.map((level) => {
          const data = state.save.levels[level.id];

          return `
            <article class="level-card ${data.unlocked ? 'unlocked' : 'locked'}">
              <img src="${asset(`${COMPLETE}/backgrounds/${level.bg}`)}" alt="" />
              <div class="level-shade"></div>
              <h2>${level.title}</h2>
              <p>${level.desc}</p>
              <div class="level-state">${data.completed ? '已完成' : data.unlocked ? '可进入' : '锁定'}</div>
              <button class="level-enter" data-action="${data.unlocked ? '进入苔藓山谷' : '锁定关卡'}">${data.unlocked ? '进入关卡' : '尚未开放'}</button>
            </article>
          `;
        }).join('')}
      </div>
    </div>
  `;
}
