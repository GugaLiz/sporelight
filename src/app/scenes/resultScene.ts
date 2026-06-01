import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState } from '../types';
import { escapeHtml } from '../ui';

const COMPLETE = COMPLETE_ASSET_ROOT;

export function renderResultScene(state: AppState) {
  return `
    <div class="screen result-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_valley.png`)}')">
      <div class="result-panel">
        <img src="${asset(`${COMPLETE}/characters/char_luvie_bow_02.png`)}" alt="" />
        <h1>苔藓山谷重新发光了</h1>
        <p>${escapeHtml(state.save.playerName)}播下的孢子长成了新的路。</p>

        <div class="unlock-row">
          <span>解锁图鉴</span>
          <strong>发光苔藓</strong>
          <strong>藤蔓桥</strong>
        </div>

        <div class="result-actions">
          <button class="primary-gem" data-action="返回关卡选择">关卡选择</button>
          <button class="small-gem" data-action="重玩">重玩</button>
          <button class="small-gem" data-action="图鉴">图鉴</button>
        </div>
      </div>
    </div>
  `;
}
