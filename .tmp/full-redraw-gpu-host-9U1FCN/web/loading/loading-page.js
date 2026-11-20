(function () {
  'use strict';
  const protocol = 'sporelight-loading-v1';
  const view = document.getElementById('loading-view');
  const progress = document.getElementById('status-progress');
  const percent = document.getElementById('load-percent');
  const label = document.getElementById('loading-label');
  const caption = document.getElementById('status-caption');
  const notice = document.getElementById('status-notice');
  const embedded = window.parent !== window;

  function render(state) {
    if (!['preparing', 'downloading', 'opening', 'ready', 'error'].includes(state.phase)) return;
    view.dataset.phase = state.phase;
    view.setAttribute('aria-busy', String(!['ready', 'error'].includes(state.phase)));
    notice.hidden = state.phase !== 'error';
    document.getElementById('progress-region').hidden = state.phase === 'error';
    document.querySelector('.loading-line').hidden = state.phase === 'error';
    caption.hidden = state.phase === 'error';
    const known = Number.isFinite(state.current) && Number.isFinite(state.total) && state.current >= 0 && state.total > 0;
    if (known) {
      progress.max = state.total;
      progress.value = Math.min(state.current, state.total);
      percent.textContent = Math.floor(progress.value / progress.max * 100) + '%';
    } else {
      progress.removeAttribute('value');
      progress.removeAttribute('max');
      percent.textContent = '';
    }
    label.textContent = state.phase === 'opening' ? '正在唤醒花园…' : state.phase === 'ready' ? '花园醒来了' : state.phase === 'downloading' ? '加载中…' : '准备加载…';
    caption.textContent = state.phase === 'opening' ? '微光已到齐，正在准备第一幅画面。' : '花园正在慢慢醒来。';
    if (state.phase === 'error') {
      document.getElementById('error-details').textContent = typeof state.message === 'string' ? state.message : '未知加载错误';
      document.getElementById('retry-button').focus({preventScroll: true});
    }
  }
  window.addEventListener('message', function (event) {
    if (!embedded || event.origin !== window.location.origin || event.source !== window.parent || event.data?.protocol !== protocol || event.data.type !== 'state') return;
    render(event.data);
  });
  document.getElementById('retry-button').addEventListener('click', function () {
    if (embedded) window.parent.postMessage({protocol, type: 'retry'}, window.location.origin);
    else window.location.reload();
  });
  view.dataset.scriptReady = 'true';
  if (embedded) window.parent.postMessage({protocol, type: 'ready'}, window.location.origin);
}());
