# Website opening sequence

The website uses pre-rendered frames of the real Apple MacBook Air 13-inch model,
with the app's own hinge articulation and Metal glass shader. The render script never captures the live desktop; it uses the supplied light/dark
screenshots as screen textures. No simulated HTML laptop or browser 3D engine is involved.

Generate the default silver sequence from the repository root:

```sh
scripts/render-website-frames.sh --output build/air-silver-new --color silver --frames 121 --width 2880 --height 2000 --background f5f5f7 --appearance light
```

Customize both the wallpaper and enclosure:

```sh
scripts/render-website-frames.sh --output build/air-midnight-new --color midnight --wallpaper /path/to/wallpaper.jpg --frames 121 --width 2880 --height 2000 --background f5f5f7 --appearance light
```

Air colours: `silver`, `skyBlue`, `starlight`, `midnight`. The asset cache defaults
to `build/apple-models`; use `--cache DIR` to change it. Missing originals are
fetched through the app's checksum-checked AppleModelCache. `--help` lists options.
Output must be a fresh directory; an existing render is never overwritten.

Inspect the closed, intermediate and open JPEGs before copying the directory to
`website/assets/`. Change the section's `data-sequence` manifest path and poster
image in `website/index.html` to switch sequences. The final frame is the poster
(`frame-120.jpg` with 121 frames). Resolution, filenames and model provenance are
recorded in `sequence.json`, written only after all frames finish. Keep the poster
width/height attributes in sync when changing the output resolution.

The scroll player uses native page scrolling with a sticky scene. Scroll position
maps to a frame in either direction; the camera stays centered and fixed for a symmetric front view. Each render
keeps 24 pixels of top clearance so the closed laptop sits close to the hero
without clipping the opening lid. The page starts at frame 14 (about 5.6 degrees, or 5% open), then scrolling advances
to frame 120. The stage initially fills the space below the hero and expands
to the available viewport as the hero scrolls away. The player crops only the
unused lower image margin to center the visible device.
Only nearby frames are decoded (12 cached, up to 3 in flight); no idle animation
loop runs. Requests pause outside the scene. Missing frames retain the last good
image. Motion is enabled by default, deliberately overriding the system Reduce Motion
preference as requested. The footer offers a native On/Off radio group; On shows
the open poster. A second radio group offers Auto/Light/Dark, defaulting to Auto
and reacting to system appearance changes. Both website preferences are saved
in localStorage. Native fieldsets, legends, radios and visible focus indicators
provide group names and standard Tab/arrow-key operation. JavaScript/network
failure leaves the poster.

Render a matching dark sequence with `--background 1d1d1f --appearance dark --finish space-gray`.
The default screen artwork comes from the shared `ExampleScreen` loader in
DuoSimulation, using the maintainer-supplied `ExampleScreens/light.png` and
`dark.png`. The app uses these same originals in onboarding and when Desktop is off;
the main app simulator defaults to the real desktop when permission is available;
the effective app appearance chooses the variant. `--wallpaper` still overrides
the shared screenshot for a one-off website render. Use separate fresh
output directories for light and dark, then set the section’s `data-sequence`
and `data-dark-sequence` paths. Both sequences must have matching dimensions,
frame counts and filenames. Website rendering disables HDR tone mapping so the constant screen material retains
the screenshot contrast. Backgrounds are composited in explicit sRGB, matching the CSS
colours. Frames default to 2880 × 2000 with JPEG quality 94%; the glass renderer
uses the source screenshot width rather than reducing it to 1536 pixels.
The dark website sequence uses `--finish space-gray`, a neutral darkening of
the silver enclosure materials for presentation. This is a custom render finish,
not an original Apple Space Gray model asset. Light uses the original silver.

The website palette and type hierarchy follow the Apple iPhone Duo page:
white, #1d1d1f text, #6e6e73 secondary text, #f5f5f7 surfaces and #0071e3 actions.
It uses the native system San Francisco typeface on macOS/iOS, with Helvetica/Arial
fallbacks elsewhere. No proprietary webfont is redistributed and no custom
letter-spacing or word-spacing is applied.

Apple logo: Simple Icons (CC0); GitHub mark: Primer Octicons (MIT). Brand marks
remain trademarks of their respective owners. Model, wallpaper and lighting
credits remain as described in CREDITS.md. Generated website frames are not
covered by the original-code MIT grant for third-party artwork.


Install a new render with content-addressed URLs (required to avoid stale browser frames):

```sh
python3 scripts/install-website-sequence.py build/new-light-render --appearance light
python3 scripts/install-website-sequence.py build/new-dark-render --appearance dark
```

The installer hashes the manifest and every frame, copies them to an immutable
asset directory and updates the HTML references, including the light poster.
Never overwrite an existing hashed directory; changed artwork gets a new URL.

### WebP distribution and preloading

Render lossless masters using `--format png`, then encode those originals (never
recompress the JPEG exports):

```sh
scripts/render-website-frames.sh --output build/masters-light --appearance light --format png
python3 scripts/encode-website-webp.py build/masters-light build/frames-light-webp
python3 scripts/install-website-sequence.py build/frames-light-webp --appearance light
```

Repeat for dark using `--appearance dark --finish space-gray --background 1d1d1f`.
The encoder uses WebP quality 92, sharp chroma conversion and preserves ICC metadata.
It shares byte-identical PNG source frames through repeated manifest entries,
without changing the 121-step timeline. Quality 92 is perceptual compression, not
mathematically lossless; `--lossless` is available for comparison. Keep masters in
ignored build directories. Resolution remains 2880 × 2000.

The browser downloads the active appearance only, starting with nearby frames,
then coarse coverage across the timeline and finally the intermediate frames.
Two background fetches supplement at most three demanded image decodes. Compressed
Blobs are retained for that appearance; only twelve decoded images are retained.
Changing appearance or enabling Reduce Motion aborts pending requests and discards
the previous compressed cache. Save-Data skips background prefetching. Theme
manifests are fetched independently because deduplication mappings can differ.
