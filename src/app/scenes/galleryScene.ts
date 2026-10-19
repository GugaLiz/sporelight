import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT } from '../constants';
import type { AppState } from '../types';

const COMPLETE = COMPLETE_ASSET_ROOT;
const galleryImage = (id: string) => `/images/production/${({ flowerbud: 'bloom', moss: 'light', vine: 'bridge', bug: 'bug', lilypad: 'lily-open', mushroom: 'glow-flower', arch: 'arch', starflower: 'bloom' } as Record<string,string>)[id]}.png`;

export const GALLERY_ITEMS: ReadonlyArray<{
  id: string;
  title: string;
  desc: string;
  image: string;
  habitat: string;
  firstFound: string;
  category: string;
}> = [
  { id: 'flowerbud', title: '萌芽花台', desc: '在古老的土壤上，沉睡的种子悄然萌发。柔嫩的花瓣承载着第一缕微光。', image: 'gallery_flowerbud.png', habitat: '乔灌草丛、湿地花园', firstFound: '第 1 章 · 苔藓山谷', category: '植物' },
  { id: 'moss', title: '发光苔藓', desc: '在暗处储存微光，愿意替旅人照亮脚边。', image: 'gallery_moss.png', habitat: '潮湿岩壁、山谷石阶', firstFound: '第 1 章 · 苔藓山谷', category: '植物' },
  { id: 'vine', title: '藤蔓桥', desc: '从一粒孢子伸展成路，连接原本不能抵达的地方。', image: 'gallery_vine.png', habitat: '深谷间隙', firstFound: '第 1 章 · 苔藓山谷', category: '道具' },
  { id: 'bug', title: '发光小虫', desc: '喜欢温暖的光，会绕着新生植物跳舞。', image: 'gallery_bug_glow.png', habitat: '微光苔原各处', firstFound: '第 1 章 · 苔藓山谷', category: '生物' },
  { id: 'lilypad', title: '睡莲', desc: '安静浮在水面，醒来时会送出一串水珠。', image: 'gallery_lilypad.png', habitat: '雨滴池塘', firstFound: '第 2 章 · 雨滴池塘', category: '植物' },
  { id: 'mushroom', title: '光菇', desc: '在洞穴里亮起，像一小盏不需要火的灯。', image: 'gallery_mushroom_light.png', habitat: '星光洞穴', firstFound: '第 3 章 · 星光洞穴', category: '植物' },
  { id: 'arch', title: '遗迹拱门', desc: '旧石头记得很久以前的回声。', image: 'gallery_ruin_arch.png', habitat: '古苔原遗迹', firstFound: '第 1 章 · 苔藓山谷', category: '道具' },
  { id: 'starflower', title: '星花', desc: '只在被温柔照亮的夜里开放。', image: 'gallery_starflower.png', habitat: '星光洞穴入口', firstFound: '第 3 章 · 星光洞穴', category: '植物' }
];

const CATEGORIES = ['全部', '植物', '生物', '道具'] as const;

export function renderGalleryScene(state: AppState) {
  const unlocked = GALLERY_ITEMS.filter((item) => state.save.gallery[item.id]);
  const total = GALLERY_ITEMS.length;
  const unlockedCount = unlocked.length;

  // Count unlocked per category
  const counts: Record<string, string> = {};
  CATEGORIES.forEach((cat) => {
    if (cat === '全部') {
      counts[cat] = `${unlockedCount}/${total}`;
    } else {
      const catItems = GALLERY_ITEMS.filter((i) => i.category === cat);
      const catUnlocked = catItems.filter((i) => state.save.gallery[i.id]).length;
      counts[cat] = `${catUnlocked}/${catItems.length}`;
    }
  });

  return `
    <div class="screen gallery-screen" style="background-image:url('/images/production/bg-valley.jpg')">
      <button class="round-nav back" data-action="返回主菜单" aria-label="返回主菜单">
        ←
      </button>

      <div class="gallery-header">
        <h1>图鉴 / 画册</h1>
        <div class="gallery-subtitle">微光苔原 · Sporelight</div>
        <div class="gallery-collected">已收集 ${unlockedCount} / ${total}</div>
        <div class="gallery-tabs">
          ${CATEGORIES.map((cat) => `
            <button class="gallery-tab ${cat === '全部' ? 'is-active' : ''}" data-gallery-cat="${cat}">
              ${cat} <span class="tab-count">${counts[cat]}</span>
            </button>
          `).join('')}
        </div>
      </div>

      <div class="gallery-book">
        <!-- Left page: item grid -->
        <div class="gallery-page gallery-page--left">
          <div class="gallery-grid" id="galleryGrid">
            ${GALLERY_ITEMS.map((item) => {
              const isUnlocked = Boolean(state.save.gallery[item.id]);
              return `
                <button class="gallery-card ${isUnlocked ? 'unlocked' : 'locked'}" data-gallery-id="${item.id}" data-category="${item.category}" ${isUnlocked ? '' : 'disabled'}>
                  <div class="gallery-art">
                    <img src="${isUnlocked ? galleryImage(item.id) : asset(`${COMPLETE}/ui/icons/ui_icon_mystery.png`)}" alt="${isUnlocked ? item.title : '未发现'}" />
                  </div>
                  <h2>${isUnlocked ? item.title : '未发现'}</h2>
                  <div class="gallery-stars">
                    ${isUnlocked ? Array.from({ length: 5 }, () => `<img src="${asset(`${COMPLETE}/gallery/gallery_star_full.png`)}" alt="★" class="star-icon" />`).join('') : Array.from({ length: 5 }, () => `<img src="${asset(`${COMPLETE}/gallery/gallery_star_empty.png`)}" alt="☆" class="star-icon" />`).join('')}
                  </div>
                </button>
              `;
            }).join('')}
          </div>
        </div>

        <!-- Right page: detail -->
        <div class="gallery-page gallery-page--right">
          <div class="gallery-detail" id="galleryDetail">
            ${renderGalleryDetail(unlocked[0] ?? null, COMPLETE)}
          </div>
        </div>
      </div>
    </div>
  `;
}

export function renderGalleryDetail(item: typeof GALLERY_ITEMS[number] | null, complete = COMPLETE) {
  if (!item) {
    return `
      <div class="gallery-detail-empty">
        <img src="${asset(`${complete}/ui/icons/ui_icon_mystery.png`)}" alt="" class="detail-empty-icon" />
        <p>选择左侧图鉴条目查看详情</p>
      </div>
    `;
  }

  return `
    <div class="gallery-detail-content">
      <h2 class="detail-title">${item.title}</h2>
      <div class="gallery-stars detail-stars">
        ${Array.from({ length: 5 }, () => `<img src="${asset(`${complete}/gallery/gallery_star_full.png`)}" alt="★" class="star-icon" />`).join('')}
      </div>
      <div class="detail-art">
        <img src="${galleryImage(item.id)}" alt="${item.title}" />
      </div>
      <p class="detail-desc">${item.desc}</p>
      <div class="detail-meta">
        <div class="meta-row">
          <span class="meta-label">栖息环境</span>
          <span class="meta-value">${item.habitat}</span>
        </div>
        <div class="meta-row">
          <span class="meta-label">首次发现</span>
          <span class="meta-value">${item.firstFound}</span>
        </div>
      </div>
    </div>
  `;
}
