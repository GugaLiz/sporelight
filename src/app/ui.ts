import { asset } from './assets';
import { COMPLETE_ASSET_ROOT } from './constants';

const C = COMPLETE_ASSET_ROOT;

export function materialIcon(name: string, className = '') {
  return `<img class="material-icon ${className}" src="/images/material-ready/icon-${name}.png" alt="" aria-hidden="true" />`;
}

export function actionButton(label: string, className: string, disabled = false) {
  return `<button class="asset-button ${className}" ${disabled ? 'disabled' : ''} data-action="${label}"><span>${label}</span></button>`;
}

/** Render an image-based button using the complete asset button PNGs (normal / hover / press). */
export function imageButton(
  label: string,
  actionKey: string,
  baseName: string,
  options: { disabled?: boolean; extraClass?: string; width?: number; height?: number } = {}
) {
  const { disabled = false, extraClass = '', width, height } = options;
  const normal = asset(`${C}/ui/buttons/${baseName}.png`);
  const hover = asset(`${C}/ui/buttons/${baseName}_hover.png`);
  const press = asset(`${C}/ui/buttons/${baseName}_press.png`);
  const disabledSrc = asset(`${C}/ui/buttons/${baseName}_disabled.png`);
  const w = width ?? 'auto';
  const h = height ?? 66;
  const style = disabled
    ? `background-image:url('${disabledSrc}');height:${h}px;${width ? `width:${w}px;` : ''}`
    : `background-image:url('${normal}');height:${h}px;${width ? `width:${w}px;` : ''}`;

  return `<button
    class="img-btn ${extraClass}"
    data-action="${actionKey}"
    data-img-normal="${normal}"
    data-img-hover="${hover}"
    data-img-press="${press}"
    data-img-disabled="${disabledSrc}"
    ${disabled ? 'disabled' : ''}
    style="${style}"
    aria-label="${label}"
  ><span class="img-btn-label">${label}</span></button>`;
}

export function bindActions(actions: Record<string, () => void>) {
  Object.entries(actions).forEach(([key, handler]) => {
    document.querySelectorAll<HTMLElement>(`[data-action="${key}"]`).forEach((element) => {
      element.addEventListener('click', handler);
    });
  });
}

/** Attach hover / press background-image swaps for all .img-btn elements. */
export function bindImageButtonEffects() {
  document.querySelectorAll<HTMLButtonElement>('.img-btn:not([disabled])').forEach((btn) => {
    const normal = btn.dataset.imgNormal ?? '';
    const hover = btn.dataset.imgHover ?? '';
    const press = btn.dataset.imgPress ?? '';

    btn.addEventListener('pointerenter', () => { btn.style.backgroundImage = `url('${hover}')`; });
    btn.addEventListener('pointerleave', () => { btn.style.backgroundImage = `url('${normal}')`; });
    btn.addEventListener('pointerdown', () => { btn.style.backgroundImage = `url('${press}')`; });
    btn.addEventListener('pointerup', () => { btn.style.backgroundImage = `url('${hover}')`; });
  });
}

export function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' })[char] ?? char);
}
