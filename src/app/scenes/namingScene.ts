import { asset } from '../assets';
import { DEFAULT_NAME, NAMING_ASSET_ROOT } from '../constants';
import type { AppState } from '../types';
import { escapeHtml } from '../ui';

const NAMING = NAMING_ASSET_ROOT;

export function renderNamingScene(state: AppState) {
  return `
    <div class="screen naming-screen" style="background-image:url('./images/production/bg-valley.jpg')">
      <img class="naming-logo" src="${asset(`${NAMING}/ui/logo/ui_logo_naming.png`)}" alt="微光苔原" />
      <img class="naming-title" src="${asset(`${NAMING}/ui/logo/ui_title_naming.png`)}" alt="为主角命名" />
      <img class="naming-luvie" src="./images/material-ready/portrait-front.png" alt="" />

      <div class="name-card">
        <p>她从微光中醒来。</p>
        <p>你想怎么称呼她？</p>

        <label class="name-input-wrap">
          <input id="playerNameInput" aria-label="角色名称" autocomplete="off" maxlength="12" value="${escapeHtml(state.save.playerName || DEFAULT_NAME)}" />
        </label>

        <p id="nameError" class="form-error" aria-live="polite"></p>
        <p class="naming-hint">→ 后续可在设置中修改名称 ←</p>

        <div class="naming-actions">
          <button class="small-gem" data-action="randomName">随机名字</button>
          <button class="small-gem" data-action="resetNameField">恢复默认</button>
        </div>

        <button class="primary-gem" data-action="startJourney">开始旅程</button>
      </div>
    </div>
  `;
}
