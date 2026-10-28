import type { AppState } from '../types';
export function renderBootScene(state: AppState) {
  return `<div class="screen journey-boot" style="background-image:url('./images/main/bg.png')"><div class="boot-soften"></div><div class="boot-content"><span class="eyebrow">EVERY JOURNEY BEGINS WITH A SPORE</span><h1>微光苔原</h1><p>S P O R E L I G H T</p><img src="./images/production/idle1.png" alt="露薇"/><div class="boot-line"></div><small role="status">${state.bootReady ? '微光准备好了。' : '正在唤醒沉睡的苔原…'}</small></div></div>`;
}
