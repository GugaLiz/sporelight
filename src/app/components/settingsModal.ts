import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState, ConfirmMode, Quality } from '../types';

const COMPLETE = COMPLETE_ASSET_ROOT;

type SliderSetting = 'bgm' | 'sfx' | 'ambient';
type ToggleSetting = 'dynamicLight' | 'particles' | 'lowMotion' | 'vibration' | 'fullscreen';

export function renderSettingsModal(state: AppState) {
  return `
    <div class="settings-layer" role="dialog" aria-modal="true">
      <div class="settings-modal">
        <button class="settings-close" data-action="关闭设置" aria-label="关闭设置"></button>

        <header class="settings-header">
          <h1><span>设置</span></h1>
          <p>Sporelight Settings</p>
        </header>

        <div class="settings-body">
          <aside class="settings-companion">
            <div class="settings-character-scene">
              <img class="settings-firefly" src="${asset(`${COMPLETE}/fx/fx_glow_critter.png`)}" alt="" />
              <img class="settings-luvie" src="${asset(`${COMPLETE}/characters/char_luvie_front.png`)}" alt="" />
              <img class="settings-platform" src="${asset(`${COMPLETE}/world/world_moss_bright.png`)}" alt="" />
            </div>

            <p class="settings-poem-text">在微光的陪伴下，<br />每一刻都将变得温柔而美好。</p>
            <div class="settings-ornament"></div>
          </aside>

          <div class="settings-content">
            <section class="settings-card audio-card">
              <h2><span>♪</span>音频<i></i></h2>
              ${renderSettingsSlider('bgm', '背景音乐', state.save.settings.bgm)}
              ${renderSettingsSlider('sfx', '音效音量', state.save.settings.sfx)}
              ${renderSettingsSlider('ambient', '环境音', state.save.settings.ambient)}
            </section>

            <section class="settings-card video-card">
              <h2><span>▣</span>画面<i></i></h2>
              <div class="settings-row">
                <span class="setting-label">画质</span>
                <div class="quality-tabs">
                  ${renderQualityTab(state.save.settings.quality, 'soft', '柔和')}
                  ${renderQualityTab(state.save.settings.quality, 'standard', '标准')}
                  ${renderQualityTab(state.save.settings.quality, 'hd', '高清')}
                </div>

                <div class="settings-toggle-column">
                  ${renderSettingsToggle('dynamicLight', '动态光效', state.save.settings.dynamicLight)}
                  ${renderSettingsToggle('particles', '粒子效果', state.save.settings.particles)}
                  ${renderSettingsToggle('lowMotion', '低动态模式', state.save.settings.lowMotion)}
                </div>
              </div>
            </section>

            <section class="settings-card operation-card">
              <h2><span>☝</span>操作<i></i></h2>
              <div class="settings-row">
                <label class="language-row frequency-row">
                  <span>提示频率</span>
                  <select id="hintFrequencySelect">
                    <option>适中</option>
                    <option>较少</option>
                    <option>频繁</option>
                  </select>
                </label>

                <div class="dialog-speed">
                  <span>对话速度</span>
                  <div class="quality-tabs">
                    <button type="button">舒缓</button>
                    <button type="button" class="active">标准</button>
                    <button type="button">快速</button>
                  </div>
                </div>

                ${renderSettingsToggle('vibration', '震动反馈', state.save.settings.vibration)}
              </div>
            </section>

            <section class="settings-card general-card">
              <h2><span>⚙</span>通用<i></i></h2>
              <div class="settings-row">
                <label class="language-row">
                  <span>语言</span>
                  <select id="languageSelect">
                    <option value="zh-CN" ${state.save.settings.language === 'zh-CN' ? 'selected' : ''}>简体中文</option>
                    <option value="zh-TW" ${state.save.settings.language === 'zh-TW' ? 'selected' : ''}>繁體中文</option>
                    <option value="en" ${state.save.settings.language === 'en' ? 'selected' : ''}>English</option>
                  </select>
                </label>

                ${renderSettingsToggle('fullscreen', '全屏模式', state.save.settings.fullscreen)}

                <div class="settings-buttons">
                  <button class="settings-sub-button" data-action="重置名称">重置角色名称</button>
                  <button class="settings-sub-button" data-action="恢复默认设置">恢复默认设置</button>
                </div>
              </div>
            </section>
          </div>
        </div>

        <footer class="settings-footer">
          <button class="footer-button cancel" data-action="关闭设置">取消</button>
          <button class="footer-button restore" data-action="恢复默认设置">恢复默认</button>
          <button class="footer-button confirm" data-action="关闭设置">确认</button>
        </footer>

        <div class="settings-version">Ver 0.9.1</div>
        ${state.confirmMode ? renderConfirmDialog(state.confirmMode) : ''}
      </div>
    </div>
  `;
}

function renderSettingsSlider(key: SliderSetting, label: string, value: number) {
  return `
    <label class="settings-slider">
      <span>${label}</span>
      <input type="range" min="0" max="100" value="${Math.round(value * 100)}" data-setting-slider="${key}" />
      <em>${Math.round(value * 100)}%</em>
    </label>
  `;
}

function renderSettingsToggle(key: ToggleSetting, label: string, active: boolean) {
  return `
    <button class="toggle-row ${active ? 'active' : ''}" data-setting-toggle="${key}">
      <span>${label}</span>
      <i></i>
    </button>
  `;
}

function renderQualityTab(current: Quality, value: Quality, label: string) {
  return `<button class="${current === value ? 'active' : ''}" data-quality="${value}">${label}</button>`;
}

function renderConfirmDialog(confirmMode: Exclude<ConfirmMode, null>) {
  const text = confirmMode === 'resetName' ? '将角色名称恢复为“露薇”？' : '将设置恢复为默认值？';

  return `
    <div class="confirm-mask">
      <div class="confirm-dialog">
        <p>${text}</p>
        <div>
          <button data-action="取消确认">取消</button>
          <button data-action="确认操作">确认</button>
        </div>
      </div>
    </div>
  `;
}
