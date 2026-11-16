// This script is injected only by the local preview middleware, never exported.
if (['localhost','127.0.0.1','[::1]'].includes(location.hostname)) {
 const style=document.createElement('link');
 style.rel='stylesheet';style.href='/__standards/entry.css';document.head.append(style);
 const link=document.createElement('a');
 link.id='sporelight-standards-entry';link.href='/__standards/';link.target='_blank';link.rel='noopener';
 link.textContent='元素手册 ↗';link.title='查看本地游戏元素与开发标准（新标签页）';
 link.setAttribute('aria-label','元素手册，在新标签页查看本地开发标准');document.body.append(link);
}
