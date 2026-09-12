(() => {
  // Keep local previews and other GitHub Pages projects out of this site's reports.
  if (window.location.origin !== 'https://roelvangils.github.io' ||
      !window.location.pathname.startsWith('/magic-hinge/')) return;

  const queue = window._paq = window._paq || [];
  queue.push(['disableCookies']);
  queue.push(['setDoNotTrack', true]);
  queue.push(['setTrackerUrl', 'https://stats.11ways.be/matomo.php']);
  queue.push(['setSiteId', '7']);
  queue.push(['setDomains', ['roelvangils.github.io/magic-hinge/']]);
  queue.push(['trackPageView']);
  queue.push(['enableLinkTracking']);

  const script = document.createElement('script');
  script.async = true;
  script.src = 'https://stats.11ways.be/matomo.js';
  document.head.appendChild(script);
})();
