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
  document.querySelectorAll('#download, #download-install').forEach(download => {
    download.href = release.url; download.hidden = false;
  });
  document.querySelector('#release-status').textContent = release.displayVersion || `Version ${release.version}`;
  document.querySelector('#version').textContent = release.displayVersion || `v${release.version}`;
}).catch(() => { /* The HTML retains the last verified release link when offline. */ });

// The scroll position selects pre-rendered geometry; wheel/touch remain native.
// Decode a small moving window rather than retaining the whole sequence in RAM.
(async function hingeSequence() {
  const story = document.querySelector('.hinge-story');
  const canvas = document.querySelector('#hinge-canvas');
  const poster = document.querySelector('#hinge-poster');
  const hint = document.querySelector('#scroll-hint');
  const caption = document.querySelector('#story-copy');
  const play = story.querySelector('.play-scroll');
  const pill = story.querySelector('.interaction-pill');
  const root = document.documentElement;
  let theme = root.dataset.theme;
  const updateDescription = () => { poster.alt = `A ${theme === 'dark' ? 'dark gray' : 'silver'} 13-inch MacBook Air opening to reveal the Magic Hinge glass effect on a ${theme === 'dark' ? 'dark' : 'light'} example desktop.`; };
  updateDescription();
  const context = canvas.getContext('2d', { alpha: false });
  let layoutDirty = true, geometry, stageHeight = 0;
  function fallback() {
    layoutDirty = true;
    root.dataset.sequence = 'fallback';
    story.classList.remove('is-animated');
    story.firstElementChild.style.height = ''; stageHeight = 0;
  }
  if (!context) { fallback(); return; }
  function layoutStage() {
    const stage = story.firstElementChild;
    if (layoutDirty) {
      const rect = story.getBoundingClientRect();
      geometry = {storyTop:rect.top+scrollY, storyHeight:rect.height,
        headerHeight:document.querySelector('.site-header').offsetHeight,
        width:stage.clientWidth, viewport:innerHeight,
        bottom:parseFloat(getComputedStyle(story.querySelector('.hinge-visual')).bottom)};
      layoutDirty = false;
    }
    const {storyTop,headerHeight,viewport} = geometry;
    const available = Math.max(280,viewport-storyTop);
    const expanded = Math.max(280,viewport-headerHeight);
    const reveal = Math.max(0,Math.min(1,scrollY/Math.max(1,storyTop-headerHeight)));
    const height = available+(expanded-available)*reveal;
    if (stageHeight !== height) { stage.style.height = `${height}px`; stageHeight = height; }
    return geometry;
  }

  // Reserve the final stage geometry before awaiting any network resources.
  if (root.dataset.reduceMotion !== 'on') { story.classList.add('is-animated'); layoutStage(); }
  let manifest;
  let manifestURL = new URL(theme === 'dark' ? story.dataset.darkSequence : story.dataset.sequence, location.href);
  const firstFrame = 10; // About 3°: matches the top of the gentle idle movement.
  let previewFrame;
  const manifests = new Map();
  try {
    const framingResponse = await fetch('sequence-framing.json');
    if (!framingResponse.ok) throw new Error('Framing unavailable');
    const framing = await framingResponse.json();
    for (const [scrollPath,idlePath] of [[story.dataset.sequence,story.dataset.idleSequence],[story.dataset.darkSequence,story.dataset.darkIdleSequence]]) {
      const sequences = await Promise.all([scrollPath,idlePath].map(async path => {
        const url = new URL(path,location.href);
        const response = await fetch(url);
        if (!response.ok) throw new Error('Sequence unavailable');
        const m = await response.json();
        if (!Array.isArray(m.frames) || m.frames.length < 2 || m.frames.length > 361 ||
            !m.frames.every(name => /^frame-\d{3}\.(jpg|webp)$/.test(name)) ||
            !Number.isInteger(m.width) || m.width < 320 || m.width > 3840 ||
            !Number.isInteger(m.height) || m.height < 240 || m.height > 2160 || !m.frames.includes(m.poster)) throw new Error('Invalid sequence');
        const measured = framing[path];
        if (!measured || measured.width !== m.width || measured.height !== m.height || measured.bounds.length !== m.frames.length || !measured.bounds.every(b=>Array.isArray(b)&&b.length===2&&b.every(Number.isFinite)&&b[0]>=0&&b[1]<=1&&b[0]<b[1])) throw new Error('Invalid framing');
        return {...m, bounds:measured.bounds, frames:m.frames.map(name => new URL(name,url).href), poster:new URL(m.poster,url).href};
      }));
      const [scroll,idle] = sequences;
      if (scroll.width !== idle.width || scroll.height !== idle.height || idle.motion !== 'idle' || idle.maximumAngle !== 3) throw new Error('Mismatched idle sequence');
      manifests.set(new URL(scrollPath,location.href).href,{...scroll,scrollCount:scroll.frames.length,idleCount:idle.frames.length,frames:[...scroll.frames,...idle.frames],bounds:[...scroll.bounds,...idle.bounds.map(()=>idle.bounds[idle.bounds.length-1])]});
    }
    manifest = manifests.get(manifestURL.href);
    if ([...manifests.values()].some(m => m.width !== manifest.width || m.height !== manifest.height || m.frames.length !== manifest.frames.length || m.scrollCount !== manifest.scrollCount)) throw new Error('Mismatched appearances');
  } catch { fallback(); return; }
  previewFrame = manifest.frames[firstFrame];
  poster.src = new URL(previewFrame,manifestURL).href;
  canvas.width = manifest.width; canvas.height = Math.round(manifest.height*0.86);
  // Bounds are measured at build time. No pixel readback or layout reads in RAF.
  function drawFrame(image, index) {
    const scale = Math.min(1,(canvas.height-120)/manifest.height);
    const [top,bottom] = manifest.bounds[index];
    const offset = (canvas.height-(top+bottom)*manifest.height*scale)/2;
    context.fillStyle = '#'+manifest.background;
    context.fillRect(0,0,canvas.width,canvas.height);
    context.drawImage(image,(canvas.width-manifest.width*scale)/2,offset,manifest.width*scale,manifest.height*scale);
    return offset+top*manifest.height*scale;
  }
  function positionPill(index) {
    const scale = Math.min(1,(canvas.height-120)/manifest.height);
    const [top,bottom] = manifest.bounds[index];
    const firstTop = (canvas.height-(top+bottom)*manifest.height*scale)/2+top*manifest.height*scale;
    const available = stageHeight-geometry.bottom;
    const height = Math.min(available,geometry.width*canvas.height/canvas.width);
    pill.style.top = `${Math.max(4,(available-height)/2+height*firstTop/canvas.height-60)}px`;
  }
  const cache = new Map();
  const failed = new Set();
  const loading = new Map();
  let target = 0, drawn = -1, scheduled = false, visible = false;
  let previousTarget = 0, direction = 1;
  const last = manifest.scrollCount - 1;
  let broken = false, generation = 0;
  const enabled = () => !broken && root.dataset.reduceMotion !== 'on';
  let playback = 0, idleStarted = null, lastInteraction = performance.now();
  function stopPlayback() {
    lastInteraction = performance.now(); idleStarted = null;
    cancelAnimationFrame(playback);
    playback = 0;
  }
  play.addEventListener('click', () => {
    stopPlayback();
    if (!enabled()) return;
    const headerHeight = document.querySelector('.site-header').offsetHeight;
    const rect = story.getBoundingClientRect();
    const closing = canvas.dataset.idle !== 'true' && target >= Math.round(last*0.85);
    const destination = closing ? 0 : rect.top + scrollY + rect.height - Math.max(280, innerHeight-headerHeight) - headerHeight;
    const from = scrollY;
    if (Math.abs(destination-from) < 1) return;
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
    const order = [firstFrame, last, 0, firstFrame-1];
    for (let i=firstFrame; i<=last; i+=8) order.push(i);
    if (scrollY < 2) {
      order.push(manifest.frames.length-1,last+1);
      for (let i=last+1;i<manifest.frames.length;i+=12) order.push(i);
      for (let i=last+1;i<manifest.frames.length;i++) order.push(i);
    }
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
      theme = root.dataset.theme; updateDescription(); generation++; resetDownloads(); layoutDirty = true;
      manifestURL = new URL(theme === 'dark' ? story.dataset.darkSequence : story.dataset.sequence,location.href);
      manifest = manifests.get(manifestURL.href); previewFrame = manifest.frames[firstFrame];
      poster.src = new URL(enabled() ? previewFrame : manifest.poster,manifestURL).href;
      cache.clear(); loading.clear(); failed.clear(); drawn = -1;
      canvas.hidden = true; poster.hidden = false; root.dataset.sequence = 'loading';
    }
    if (!enabled()) {
      stopPlayback(); play.hidden = true; pill.hidden = true; canvas.dataset.idle = 'false';
      if (downloads.size) { generation++; resetDownloads(); layoutDirty = true; loading.clear(); }
      fallback(); canvas.hidden = true; poster.hidden = false;
      poster.src = new URL(manifest.poster,manifestURL).href;
      hint.hidden = true; caption.textContent = 'Your desktop, with a little magic.';
      cache.clear(); drawn = -1; return;
    }
    if (!story.classList.contains('is-animated')) layoutDirty = true;
    story.classList.add('is-animated');
    play.hidden = drawn < 0; pill.hidden = drawn < 0;
    if (drawn < 0) root.dataset.sequence = 'loading';
    const {storyHeight,headerHeight,storyTop} = layoutStage();
    // Start as the device enters view, instead of waiting for the sticky pin.
    const start = Math.max(0,storyTop-innerHeight*0.65);
    const end = storyTop + storyHeight-stageHeight-headerHeight;
    const progress = Math.max(0,Math.min(1,(scrollY-start)/Math.max(1,end-start)));
    target = Math.round(firstFrame+(last-firstFrame)*progress);
    const idleEligible = visible && scrollY < 2 && !playback && document.visibilityState === 'visible';
    if (idleEligible && performance.now()-lastInteraction >= 1500) {
      idleStarted ??= performance.now();
      const opening = (1+Math.cos((performance.now()-idleStarted)*2*Math.PI/6000))/2;
      target = last+1+Math.round(opening*(manifest.idleCount-1));
    } else { idleStarted = null; }
    const isIdle = idleEligible && idleStarted !== null;
    canvas.dataset.idle = String(isIdle);
    if (target !== previousTarget) direction = Math.sign(target-previousTarget);
    previousTarget = target;
    play.setAttribute('aria-label', !isIdle && target >= Math.round(last*0.85) ? 'Close the MacBook' : 'Open the MacBook');
    hint.hidden = progress > .12;
    caption.textContent = progress < .22 ? 'A glimpse of the magic. Keep scrolling.' : progress < .78 ? 'Watch your desktop turn to glass.' : '';
    if (!visible) return;
    // Late decodes must not freeze presentation or pull a moving lid backwards.
    const sameSequence = index => isIdle ? index > last : index <= last;
    const candidates = [...cache.keys()].filter(index => sameSequence(index) &&
      (direction > 0 ? index <= target : index >= target) &&
      (drawn < 0 || !sameSequence(drawn) || (direction > 0 ? index >= drawn : index <= drawn)));
    const candidate = candidates.sort((a,b)=>Math.abs(a-target)-Math.abs(b-target))[0];
    if (candidate !== undefined && candidate !== drawn) {
      drawFrame(cache.get(candidate),candidate);
      root.dataset.sequence = 'ready'; play.hidden = false; pill.hidden = false;
      drawn = candidate; canvas.dataset.frame = String(candidate); canvas.hidden = false; poster.hidden = true;
    }
    if (drawn >= 0) positionPill(drawn);
    const wanted = [target];
    // Decode ahead in the direction of travel, retaining a short reversal cushion.
    for (let distance=1; distance<=9; distance++) wanted.push(target+distance*direction);
    for (let distance=1; distance<=2; distance++) wanted.push(target-distance*direction);
    for (const index of wanted) {
      if (loading.size >= 3) break;
      if (index < 0 || index >= manifest.frames.length || !sameSequence(index) || cache.has(index) || loading.has(index) || failed.has(index)) continue;
      load(index);
    }
    prefetch();
    if (idleEligible) schedule();
    // Complete failure leaves the static fallback and no dead pinned scroll area.
    if (failed.has(target) && drawn === -1 && loading.size === 0) {
      broken = true; schedule();
    }
  }
  const observer = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; if (visible) schedule(); }, {rootMargin:'300px'});
  observer.observe(story);
  addEventListener('scroll',schedule,{passive:true});
  addEventListener('resize',()=>{layoutDirty=true;schedule();},{passive:true});
  new ResizeObserver(()=>{layoutDirty=true;schedule();}).observe(document.querySelector('.hero'));
  addEventListener('websitepreferenceschange',schedule);
  document.addEventListener('visibilitychange',schedule);
  schedule();
})();
