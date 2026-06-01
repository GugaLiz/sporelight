import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState } from '../types';

const COMPLETE = COMPLETE_ASSET_ROOT;

const GALLERY_ITEMS: ReadonlyArray<[string, string, string, string]> = [
  ['flowerbud', '萌芽花台', '沉睡的花苞会在微光里慢慢舒展。', 'gallery_flowerbud.png'],
  ['moss', '发光苔藓', '在暗处储存微光，愿意替旅人照亮脚边。', 'gallery_moss.png'],
  ['vine', '藤蔓桥', '从一粒孢子伸展成路，连接原本不能抵达的地方。', 'gallery_vine.png'],
  ['bug', '发光小虫', '喜欢温暖的光，会绕着新生植物跳舞。', 'gallery_bug_glow.png'],
  ['lilypad', '睡莲', '安静浮在水面，醒来时会送出一串水珠。', 'gallery_lilypad.png'],
  ['mushroom', '光菇', '在洞穴里亮起，像一小盏不需要火的灯。', 'gallery_mushroom_light.png'],
  ['arch', '遗迹拱门', '旧石头记得很久以前的回声。', 'gallery_ruin_arch.png'],
  ['starflower', '星花', '只在被温柔照亮的夜里开放。', 'gallery_starflower.png']
];

export function renderGalleryScene(state: AppState) {
  return `
    <div class="screen gallery-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_gallery.png`)}')">
      <button class="round-nav back" data-action="返回主菜单">返回</button>
      <button class="round-nav settings" data-action="设置">设置</button>
      <h1>微光图鉴</h1>

      <div class="gallery-grid">
        ${GALLERY_ITEMS.map(([id, title, desc, image]) => {
          const unlocked = Boolean(state.save.gallery[id]);

          return `
            <article class="gallery-card ${unlocked ? 'unlocked' : 'locked'}">
              <div class="gallery-art">
                <img src="${asset(`${COMPLETE}/gallery/${unlocked ? image : 'gallery_card_normal.png'}`)}" alt="" />
              </div>
              <h2>${unlocked ? title : '尚未发现'}</h2>
              <p>${unlocked ? desc : '旅程继续时，它会慢慢现身。'}</p>
            </article>
          `;
        }).join('')}
      </div>
    </div>
  `;
}
