import { GAME_DEFAULT_TIP } from '../constants';

export function renderGameScene() {
  return `
    <div class="screen game-screen">
      <canvas id="gameCanvas" width="1280" height="720" aria-label="苔藓山谷"></canvas>

      <div class="game-hud">
        <button class="hud-button" data-action="返回关卡选择">返回</button>
        <div class="hud-title">苔藓山谷</div>
        <button class="hud-button" data-action="设置">设置</button>
      </div>

      <div class="game-tip" id="gameTip">${GAME_DEFAULT_TIP}</div>

      <div class="game-actions">
        <button class="skill-button" data-action="播种">播种</button>
      </div>
    </div>
  `;
}
