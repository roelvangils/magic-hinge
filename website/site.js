'use strict';
const copy = document.querySelector('#copy');
copy.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(document.querySelector('#brew-command').textContent);
    document.querySelector('#copy-status').textContent = 'Copied to clipboard.';
  } catch {
    document.querySelector('#copy-status').textContent = 'Select the command above to copy it.';
  }
});
fetch('release.json').then(response => {
  if (!response.ok) throw new Error('Release unavailable');
  return response.json();
}).then(release => {
  if (!/^\d+\.\d+\.\d+$/.test(release.version) || !/^[a-f0-9]{64}$/.test(release.sha256)) throw new Error('Invalid release');
  const expected = `https://github.com/roelvangils/magic-hinge/releases/download/v${release.version}/Magic-Hinge-${release.version}.dmg`;
  if (release.url !== expected) throw new Error('Invalid download');
  const download = document.querySelector('#download');
  download.href = release.url; download.hidden = false;
  document.querySelector('#release-status').textContent = `Version ${release.version}`;
  document.querySelector('#version').textContent = `v${release.version}`;
}).catch(() => { /* Keep the honest preparation state until a verified release exists. */ });
