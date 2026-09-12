// Apply saved appearance before CSS paints. Motion is deliberately opt-out on this site.
(() => {
  const root = document.documentElement;
  const systemDark = matchMedia('(prefers-color-scheme: dark)');
  const read = (key, values, fallback) => {
    try { const value = localStorage.getItem(`magic-hinge.website.${key}`); return values.includes(value) ? value : fallback; }
    catch { return fallback; }
  };
  let theme = read('theme', ['auto','light','dark'], 'auto');
  let motion = read('motion', ['on','off'], 'off');
  function apply() {
    root.dataset.theme = theme === 'auto' ? (systemDark.matches ? 'dark' : 'light') : theme;
    root.dataset.reduceMotion = motion;
    window.dispatchEvent(new Event('websitepreferenceschange'));
  }
  apply();
  systemDark.addEventListener('change', apply);
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.footer-preferences input').forEach(input => {
      input.checked = input.value === (input.name === 'theme' ? theme : motion);
      input.addEventListener('change', () => {
        if (!input.checked) return;
        if (input.name === 'theme') theme = input.value; else motion = input.value;
        try { localStorage.setItem(`magic-hinge.website.${input.name}`, input.value); } catch { /* Session choice still works. */ }
        apply();
      });
    });
  });
})();
