import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState } from '../types';
import { actionButton, escapeHtml } from '../ui';

const COMPLETE = COMPLETE_ASSET_ROOT;

export function renderMainMenuScene(state: AppState) {
  return `
    <div class="screen menu-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_mainmenu.png`)}')">
      <img class="clouds" src="${asset(`${COMPLETE}/backgrounds/bg_clouds.png`)}" alt="" />
      <img class="logo menu-logo" src="${asset(`${COMPLETE}/ui/logo/ui_logo_cn_en.png`)}" alt="微光苔原 Sporelight" />
      <div class="menu-player">欢迎回来，${escapeHtml(state.save.playerName)}</div>

      <nav class="menu-actions">
        ${actionButton('开始游戏', 'btn-start')}
        ${actionButton('继续旅程', 'btn-continue', !state.save.levels.valley.completed && state.save.lastLevel !== 'valley')}
        ${actionButton('图鉴', 'btn-gallery')}
        ${actionButton('设置', 'btn-settings')}
      </nav>
    </div>
  `;
}
