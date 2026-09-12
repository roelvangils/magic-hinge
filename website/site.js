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
  document.querySelector('#release-status').textContent = release.displayVersion || `Version ${release.version}`;
  document.querySelector('#version').textContent = release.displayVersion || `v${release.version}`;
}).catch(() => { /* Keep the honest preparation state until a verified release exists. */ });

// The scroll position selects pre-rendered geometry; wheel/touch remain native.
// Decode a small moving window rather than retaining the whole sequence in RAM.
(async function hingeSequence() {
  const story = document.querySelector('.hinge-story');
  const canvas = document.querySelector('#hinge-canvas');
  const poster = document.querySelector('#hinge-poster');
  const hint = document.querySelector('#scroll-hint');
  const caption = document.querySelector('#story-copy');
  const play = story.querySelector('.play-scroll');
  const root = document.documentElement;
  let theme = root.dataset.theme;
  const updateDescription = () => { poster.alt = `A ${theme === 'dark' ? 'dark gray' : 'silver'} 13-inch MacBook Air opening to reveal the Magic Hinge glass effect on a ${theme === 'dark' ? 'dark' : 'light'} example desktop.`; };
  updateDescription();
  const context = canvas.getContext('2d', { alpha: false });
  if (!context) return;
  let manifest;
  let manifestURL = new URL(theme === 'dark' ? story.dataset.darkSequence : story.dataset.sequence, location.href);
  const firstFrame = 29; // About 22°: 20% of the sequence's 110° fully open pose.
  let previewFrame;
  const manifests = new Map();
  try {
    for (const path of [story.dataset.sequence, story.dataset.darkSequence]) {
      const url = new URL(path, location.href);
      const response = await fetch(url);
      if (!response.ok) return;
      manifests.set(url.href, await response.json());
    }
    manifest = manifests.get(manifestURL.href);
    for (const manifest of manifests.values()) {
    if (!Array.isArray(manifest.frames) || manifest.frames.length <= firstFrame || manifest.frames.length > 361 ||
        !manifest.frames.every(name => /^frame-\d{3}\.(jpg|webp)$/.test(name)) ||
        !Number.isInteger(manifest.width) || manifest.width < 320 || manifest.width > 3840 ||
        !Number.isInteger(manifest.height) || manifest.height < 240 || manifest.height > 2160 || !manifest.frames.includes(manifest.poster)) return;
    }
    if ([...manifests.values()].some(m => m.width !== manifest.width || m.height !== manifest.height || m.frames.length !== manifest.frames.length)) return;
  } catch { return; }
  previewFrame = manifest.frames[firstFrame];
  poster.src = new URL(previewFrame,manifestURL).href;
  canvas.width = manifest.width; canvas.height = Math.round(manifest.height*0.86);
  // Rendered frames have top-aligned artwork. Center the device, not its blank canvas.
  const framing = new WeakMap();
  const boundsCanvas = document.createElement('canvas');
  boundsCanvas.width = 288; boundsCanvas.height = 200;
  const boundsContext = boundsCanvas.getContext('2d', {willReadFrequently:true});
  function drawFrame(image) {
    const background = manifest.background || (theme === 'dark' ? '1d1d1f' : 'f5f5f7');
    // Use one scale throughout the sequence; even the full source height fits
    // with a safety margin, so the opening animation never clips or pulses in size.
    const scale = Math.min(1, (canvas.height-120)/manifest.height);
    let offset = framing.get(image);
    if (offset === undefined) {
      boundsContext.drawImage(image,0,0,288,200);
      const pixels = boundsContext.getImageData(0,0,288,200).data;
      const rgb = [0,2,4].map(i => parseInt(background.slice(i,i+2),16));
      let top = 200, bottom = 0;
      for (let y=0; y<200; y++) {
        let occupied = 0;
        for (let x=0; x<288; x++) {
          const i = (y*288+x)*4;
          // Include the floating shadow, excluding only near-background compression noise.
          if (Math.max(Math.abs(pixels[i]-rgb[0]),Math.abs(pixels[i+1]-rgb[1]),Math.abs(pixels[i+2]-rgb[2])) > 8) occupied++;
        }
        if (occupied >= 6) { top = Math.min(top,y); bottom = y+1; }
      }
      offset = bottom > top ? (canvas.height-(top+bottom)*manifest.height/200*scale)/2 : 60;
      framing.set(image,offset);
    }
    context.fillStyle = '#'+background;
    context.fillRect(0,0,canvas.width,canvas.height);
    context.drawImage(image,(canvas.width-manifest.width*scale)/2,offset,manifest.width*scale,manifest.height*scale);
  }
  const cache = new Map();
  const failed = new Set();
  const loading = new Map();
  let target = 0, drawn = -1, scheduled = false, visible = false;
  const last = manifest.frames.length - 1;
  let broken = false, generation = 0;
  const enabled = () => !broken && root.dataset.reduceMotion !== 'on';
  let playback = 0;
  function stopPlayback() {
    cancelAnimationFrame(playback);
    playback = 0;
  }
  play.addEventListener('click', () => {
    stopPlayback();
    if (!enabled()) return;
    const headerHeight = document.querySelector('.site-header').offsetHeight;
    const rect = story.getBoundingClientRect();
    const destination = rect.top + scrollY + rect.height - Math.max(280, innerHeight-headerHeight) - headerHeight;
    const from = scrollY;
    if (destination <= from) return;
    const started = performance.now();
    function advance(now) {
      const progress = Math.min(1, (now-started)/1800);
      const eased = progress*progress*(3-2*progress);
      // Actual scrolling drives the same frame renderer as a wheel or trackpad.
      window.scrollTo({top: from+(destination-from)*eased, behavior: 'instant'});
      playback = progress < 1 ? requestAnimationFrame(advance) : 0;
    }
    playback = requestAnimationFrame(advance);
  });
  addEventListener('wheel', stopPlayback, {passive:true});
  addEventListener('touchstart', stopPlayback, {passive:true});
  addEventListener('pointerdown', stopPlayback, {passive:true});
  addEventListener('keydown', event => {
    if (['Escape','ArrowUp','ArrowDown','PageUp','PageDown','Home','End',' '].includes(event.key)) stopPlayback();
  });
  addEventListener('resize', stopPlayback, {passive:true});
  addEventListener('websitepreferenceschange', stopPlayback);
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(update);
  }
  // Retain compressed downloads separately from the small decoded image window.
  let downloads = new Map(), controller = new AbortController(), prefetching = 0;
  function download(index) {
    const url = new URL(manifest.frames[index], manifestURL).href;
    if (!downloads.has(url)) downloads.set(url, fetch(url, {signal:controller.signal})
      .then(response => { if (!response.ok) throw new Error('Frame unavailable'); return response.blob(); }));
    return downloads.get(url);
  }
  function prefetch() {
    if (!visible || !enabled() || navigator.connection?.saveData) return;
    // Coarse coverage first makes a quick jump useful, then fill all intermediate poses.
    const order = [firstFrame, last];
    for (let i=firstFrame; i<=last; i+=8) order.push(i);
    for (let i=firstFrame; i<=last; i++) order.push(i);
    const token = generation;
    for (const index of order) {
      if (prefetching >= 2) break;
      if (downloads.has(new URL(manifest.frames[index],manifestURL).href)) continue;
      prefetching++;
      download(index).catch(() => {}).finally(() => {
        if (token !== generation) return;
        prefetching--; prefetch();
      });
    }
  }
  function resetDownloads() {
    controller.abort(); controller = new AbortController(); downloads = new Map(); prefetching = 0;
  }
  function load(index) {
    const image = new Image();
    const token = generation;
    loading.set(index,image);
    image.decoding = 'async';
    let objectURL;
    download(index).then(blob => {
      if (token !== generation) return;
      objectURL = URL.createObjectURL(blob); image.src = objectURL;
      return image.decode();
    }).then(() => {
      if (token !== generation) return;
      cache.set(index, image);
      // At most 12 decoded frames (plus 3 inflight); distant frames are discarded.
      while (cache.size > 12) {
        const furthest = [...cache.keys()].sort((a,b) => Math.abs(b-target)-Math.abs(a-target))[0];
        cache.delete(furthest);
      }
    }).catch(() => { if (token === generation) failed.add(index); }).finally(() => { if (objectURL) URL.revokeObjectURL(objectURL); if (loading.get(index) === image) loading.delete(index); schedule(); });
  }
  function update() {
    scheduled = false;
    if (theme !== root.dataset.theme) {
      theme = root.dataset.theme; updateDescription(); generation++; resetDownloads();
      manifestURL = new URL(theme === 'dark' ? story.dataset.darkSequence : story.dataset.sequence,location.href);
      manifest = manifests.get(manifestURL.href); previewFrame = manifest.frames[firstFrame];
      poster.src = new URL(enabled() ? previewFrame : manifest.poster,manifestURL).href;
      cache.clear(); loading.clear(); failed.clear(); drawn = -1;
      canvas.hidden = true; poster.hidden = false;
    }
    if (!enabled()) {
      stopPlayback(); play.hidden = true;
      if (downloads.size) { generation++; resetDownloads(); loading.clear(); }
      story.classList.remove('is-animated'); canvas.hidden = true; poster.hidden = false;
      poster.src = new URL(manifest.poster,manifestURL).href;
      hint.hidden = true; caption.textContent = 'Your desktop, with a little magic.';
      cache.clear(); drawn = -1; return;
    }
    story.classList.add('is-animated');
    play.hidden = false;
    const rect = story.getBoundingClientRect();
    const stage = story.firstElementChild;
    const headerHeight = document.querySelector('.site-header').offsetHeight;
    const storyTop = rect.top + scrollY;
    // Center the first glimpse below the hero; use the full viewport as it scrolls away.
    const available = Math.max(280,innerHeight-storyTop);
    const expanded = Math.max(280,innerHeight-headerHeight);
    const reveal = Math.max(0,Math.min(1,scrollY/Math.max(1,storyTop-headerHeight)));
    stage.style.height = `${available+(expanded-available)*reveal}px`;
    // Start as the device enters view, instead of waiting for the sticky pin.
    const start = Math.max(0,storyTop-innerHeight*0.65);
    const end = storyTop + rect.height-stage.offsetHeight-headerHeight;
    const progress = Math.max(0,Math.min(1,(scrollY-start)/Math.max(1,end-start)));
    target = Math.round(firstFrame+(last-firstFrame)*progress);
    hint.hidden = progress > .12;
    caption.textContent = progress < .22 ? 'A glimpse of the magic. Keep scrolling.' : progress < .78 ? 'Watch your desktop turn to glass.' : '';
    if (!visible) return;
    // Keep the last good frame visible during a fast scroll or a failed request.
    if (cache.has(target) && target !== drawn) {
      drawFrame(cache.get(target));
      drawn = target; canvas.dataset.frame = String(target); canvas.hidden = false; poster.hidden = true;
    }
    const wanted = [target];
    for (let distance=1; distance<=5; distance++) wanted.push(target+distance,target-distance);
    for (const index of wanted) {
      if (loading.size >= 3) break;
      if (index < 0 || index > last || cache.has(index) || loading.has(index) || failed.has(index)) continue;
      load(index);
    }
    prefetch();
    // Complete failure leaves the static fallback and no dead pinned scroll area.
    if (failed.has(target) && drawn === -1 && loading.size === 0) {
      broken = true; schedule();
    }
  }
  const observer = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; if (visible) schedule(); }, {rootMargin:'300px'});
  observer.observe(story);
  addEventListener('scroll',schedule,{passive:true});
  addEventListener('resize',schedule,{passive:true});
  addEventListener('websitepreferenceschange',schedule);
  schedule();
})();
