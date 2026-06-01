export function actionButton(label: string, className: string, disabled = false) {
  return `<button class="asset-button ${className}" ${disabled ? 'disabled' : ''} data-action="${label}"><span>${label}</span></button>`;
}

export function bindActions(actions: Record<string, () => void>) {
  Object.entries(actions).forEach(([key, handler]) => {
    document.querySelectorAll<HTMLElement>(`[data-action="${key}"]`).forEach((element) => {
      element.addEventListener('click', handler);
    });
  });
}

export function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' })[char] ?? char);
}
