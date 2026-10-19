(() => {
  const selector = document.getElementById('theme');
  const apply = value => {
    if (value === 'auto') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.dataset.theme = value;
    selector.value = value;
  };
  try {
    const value = localStorage.getItem('stm32-flasher-theme');
    if (['auto', 'light', 'dark'].includes(value)) apply(value);
  } catch (_) { /* Storage may be unavailable in a local preview. */ }
  selector.addEventListener('change', () => {
    apply(selector.value);
    try { localStorage.setItem('stm32-flasher-theme', selector.value); } catch (_) { }
  });
})();
