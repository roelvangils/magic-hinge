# Magic Hinge

A little magic in your MacBook hinge. Tilt the screen and watch your desktop
bend, soften and fade like frosted glass. Hold still and it settles back into place.

Magic Hinge is free, open source, and available in English and Dutch.
**0.9 Beta** is the first public prerelease. It is experimental, not a stable
release. Hardware, permissions, VoiceOver and macOS 14.2 runtime checks remain
open; see [the release report](docs/release-review.md).

## Requirements

Apple silicon and macOS 14.2 or later. Automatic hinge control needs a readable
Apple LAS hinge sensor, detected at runtime. A mouse, trackpad and keyboard-driven
simulator remains usable without a sensor or Screen Recording access.

The deployment target is 14.2; a runtime test on that exact version is a required
release gate and has not yet been completed. This app is not for Intel Macs.

## Install the public beta

Download the signed, notarized DMG from
[GitHub Releases](https://github.com/roelvangils/magic-hinge/releases), open it and
drag Magic Hinge to Applications. Or use the maintainer's Homebrew tap:

```sh
brew install --cask roelvangils/tap/magic-hinge
```

The app retains `be.elevenways.MacBookDuo`, preserving existing preferences and
model cache. Moving from local ad-hoc signing to Developer ID may require a
one-time reconfirmation of Screen Recording permission.

## Use

The welcome guide offers an interactive demo, optional Screen Recording access,
and a current sensor/permission status. Reopen it from Settings at any time.
No permission request appears automatically on launch.

- Move the MacBook lid to start the desktop effect; hold still for 0.4 seconds to
  let it return smoothly over 0.45 seconds.
- Pause from the menu bar. Escape stops the effect while Magic Hinge is active.
- Drag or scroll over the 3D laptop, or use its angle slider. Double-click or
  double-tap with two fingers to open/close. Arrow keys and Page Up/Down move 5°;
  Home/End open/close; Space/Return toggle. Shift slows a transition.
- Choose Air, Pro or Neo, size and color in Settings. Models download directly
  from Apple, are checked against pinned hashes and then work offline.
- The menu offers **Check for Updates…**. Automatic checks are optional;
  automatic downloads and installation are off.

Only the built-in display receives the desktop overlay. The app does not prevent
sleep or draw over the secure login screen. Experimental lock-screen diagnostics
are compiled only for development.

## Privacy and credits

Screen images stay in memory on your Mac. They are never saved or uploaded.
There is no account or analytics. See [privacy](PRIVACY.md),
[credits and asset terms](CREDITS.md) and the [MIT license](LICENSE).
Third-party assets retain their own terms and are excluded from MIT.

## Develop

Use Xcode 26 or later with Swift 6.2 or later (required by PermissionFlow).
`Package.resolved` pins PermissionFlow 2.11.2 and Sparkle 2.9.6.

```sh
swift package resolve
swift test
python3 scripts/check-localization.py
scripts/build-app.sh development
```

Build output: `build/Magic Hinge.app`. `scripts/build-app.sh release` creates an
optimized development build; `distribution` makes a clean Developer ID build.
Open `Package.swift` in Xcode. Use the packaged app to test TCC/resource behavior.

The normal test suite uses synthetic GPU images and skips the two official-asset
render tests. For the mandatory full local release check (12 downloads, 16 model
configurations, 48 angle renders plus contact frames):

```sh
scripts/verify-release-local.sh
```

The build includes no USDZ models, development screenshots or caches. Original
wallpaper resolution is preserved. Screenshot mode uses a generated example:

```sh
open "build/Magic Hinge.app" --args --example-image
```

Read [release operations](docs/releasing.md) for signing, notarisaton, EdDSA,
GitHub Pages, Homebrew and the required manual evidence. Signing stays local;
public CI and pull requests receive no release credentials.

## Source layout

- `DuoCore`: fold state, interpolation, sensor decoding, localization.
- `DuoHardware`: private Apple LAS HID reads on a dedicated serial queue.
- `DuoGraphics`: shared Metal renderer, cursor ownership and sky effects.
- `DuoSimulation`: catalog, asset cache, scene construction, shared input physics.
- `MagicHinge`: simulator presentation/controller/adapters, permissions,
  onboarding, session lifecycle, desktop overlay, ScreenCaptureKit and updater.
- `website`: dependency-free GitHub Pages site; the final artifact generates its
  release metadata and appcast together.

The development research notes under `docs/` include historical observations;
use the release report for current verification status.
