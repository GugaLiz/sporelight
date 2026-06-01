import { asset } from '../assets';
import { STARTUP_ASSET_ROOT, STARTUP_LOADING_FRAME_FILES } from '../constants';
import type { AppState } from '../types';

const STARTUP = STARTUP_ASSET_ROOT;
const BAR_PARTICLE_FILES = [
  'particle_01.png',
  'particle_02.png',
  'particle_03.png',
  'particle_04.png',
  'particle_05.png',
  'particle_06.png',
  'particle_07.png',
  'particle_08.png',
  'particle_09.png',
  'particle_10.png'
] as const;

export function renderBootScene(state: AppState) {
  const helperCopy = state.bootReady ? '' : '正在唤醒沉睡的苔原……';
  const loadingFrame = state.bootReady
    ? STARTUP_LOADING_FRAME_FILES[STARTUP_LOADING_FRAME_FILES.length - 1]
    : STARTUP_LOADING_FRAME_FILES[0];

  return `
    <div class="screen startup-screen ${state.bootReady ? 'is-ready' : 'is-loading'}">
      <img class="startup-background" src="${asset(`${STARTUP}/05_scene_objects_temp/startup_bg_redbox_removed.png`)}" alt="" />

      <div class="startup-ambience">
        <div class="startup-sunburst"></div>
        <div class="startup-haze startup-haze--left"></div>
        <div class="startup-haze startup-haze--right"></div>
      </div>

      <img class="startup-firefly startup-firefly--left" src="${asset(`${STARTUP}/04_glow_decor/fx_glow_sprite_left_top.png`)}" alt="" />
      <img class="startup-firefly startup-firefly--right" src="${asset(`${STARTUP}/04_glow_decor/fx_glow_sprite_right_mid.png`)}" alt="" />
      <img class="startup-title ${state.bootReady ? 'is-static' : ''}" src="${asset(`${STARTUP}/01_logo_title_text/logo_title_full_group.png`)}" alt="微光苔原 Sporelight" />

      <div class="startup-loading-shell">
        <div class="startup-loading-track">
          <img
            id="startupLoadingFrame"
            class="startup-loading-frame"
            src="${asset(`${STARTUP}/02_ui_loading/04-ui_loading_bar_fill_waterlux_frames/${loadingFrame}`)}"
            alt=""
            aria-hidden="true"
          />
          <div class="startup-loading-particles" aria-hidden="true">${renderBarParticles()}</div>
        </div>

        <div class="startup-loading-copy">
          <img class="startup-loading-copy-decor startup-loading-copy-decor--left" src="${asset(`${STARTUP}/02_ui_loading/ui_loading_text_decor_left.png`)}" alt="" />
          <p class="startup-loading-copy-text">正在唤醒沉睡的苔原……</p>
          <img class="startup-loading-copy-decor startup-loading-copy-decor--right" src="${asset(`${STARTUP}/02_ui_loading/ui_loading_text_decor_right.png`)}" alt="" />
        </div>

        ${helperCopy ? `<p class="startup-ready-copy" aria-live="polite">${helperCopy}</p>` : ''}
      </div>

      <div class="startup-hero" aria-hidden="true">
        <img class="startup-hero-sheet" src="${asset(`${STARTUP}/03_character/mushroom_skirt_sway_spritesheet_row.png`)}" alt="" />
      </div>
    </div>
  `;
}

function renderBarParticles() {
  return Array.from({ length: 60 }, (_, index) => {
    const file = BAR_PARTICLE_FILES[index % BAR_PARTICLE_FILES.length];
    const segment = index % 3;
    const segmentBase = segment === 0 ? 4 : segment === 1 ? 34 : 66;
    const segmentSpan = segment === 0 ? 28 : segment === 1 ? 30 : 28;
    const left = segmentBase + ((Math.floor(index / 3) * 11 + index * 3) % segmentSpan);
    const top = 50 + (-9 + ((index * 7) % 19));
    const size = 8 + ((index * 5) % 18);
    const duration = (1 + ((index * 11) % 16) / 10).toFixed(2);
    const delay = (-((index * 9) % 20) / 10).toFixed(2);
    const driftX = -14 + ((index * 3) % 29);
    const driftY = -8 + ((index * 5) % 17);
    const rotate = (index % 2 === 0 ? 1 : -1) * (10 + ((index * 11) % 18));
    const opacity = (0.58 + (index % 4) * 0.11).toFixed(2);
    const scale = (0.96 + (index % 5) * 0.1).toFixed(2);

    return `
      <img
        class="startup-bar-particle"
        src="${asset(`${STARTUP}/particles_png_10/${file}`)}"
        alt=""
        style="left:${left}%; top:${top}%; width:${size}px; --particle-duration:${duration}s; --particle-delay:${delay}s; --particle-drift-x:${driftX}px; --particle-drift-y:${driftY}px; --particle-rotate:${rotate}deg; --particle-opacity:${opacity}; --particle-scale:${scale};"
      />
    `;
  }).join('');
}
