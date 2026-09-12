# Magic Hinge 2.3.0 — release review

Status: **release candidate, not published**. Reviewed and built 12 September 2026
on Apple silicon, macOS 27.0, Swift 6.4 / Xcode 27 SDK. The deployment target is
14.2; it is not evidence of running successfully on macOS 14.2.

## Findings and changes

| Severity | Finding | Resolution | Verification |
| --- | --- | --- | --- |
| High | Older Air assets used Pro hinge coordinates; a closed Air lid fell below the chassis. | Separate Air axes, using the authored Sky Blue joints as reference. Retain native joints when present. | All 16 configurations render at 0/45/110°. Closed-lid height regression; Air 13/15 closed images inspected. |
| High | Static AR occlusion shells in Pro 16, Sky Blue Air and Neo inflated interaction/contact bounds. | Exclude non-lid shells spanning the original open display; retain actual geometry. | All official model renders, contact frames and bounded base-height regression pass. |
| High | Global key-down monitoring conflicted with the no-Input-Monitoring permission contract. | Remove global monitor. Escape remains app-local; stillness and menu pause remain. | Source inspection, existing input regressions; no global monitor in production source. |
| High | A simulator desktop texture could survive permission revocation/lock or return from an old GPU completion. | Clear captured materials and GPU images immediately; invalidate pending texture generations; cancel capture. Recheck permission/session and capture generation before returning pixels. | Code path review and capture/render tests; full real TCC revoke/restart matrix remains a release gate. |
| High | Original distribution signing used an identifier-only designated requirement. | Clean arm64 distribution build; standard Developer ID chain, hardened runtime, timestamps, inside-out nested Sparkle signing. | `codesign --verify --deep --strict`, team/requirement/rpath/architecture/resource checks pass. App and final DMG are notarized/stapled; Gatekeeper accepts both. |
| Medium | Notification ownership and the display-clock observer lacked explicit balanced cleanup. | SessionLifecycle owns registration centers/tokens and local keys. DesktopEffect owns overlay/clock/cursor; PermissionService owns permission refresh. Remove clock observer on deallocation. | Review, application launch and cursor balance regression tests. |
| Medium | Older canceled capture warmup could clear a newer task handle; stale sensor callbacks could arrive while locked. | Generation-check warmup cleanup and reject readings outside an active session. | Review and full motion/filter regressions. |
| Medium | Hidden simulator could continue loading/parsing and the main simulator stayed active under onboarding. | Cancel asset requests on hide; suspend main simulator while guide is open. Share controller/renderer/adapters with the guide. | App launch, three-step guide navigation, full simulator regressions. |
| Medium | Download failure covered the procedural fallback with a blocking error panel. | Keep fallback usable beneath a compact retry message. | Code review; offline installed-app launch. |
| Medium | PermissionFlow's Dutch supplement landed outside the actual SwiftPM bundle resource directory. | Support both flat and Contents/Resources bundle layouts before signing. | Real Foundation Bundle locale lookup returns “Schermopname” in the packaged app. |
| Medium | Optional sparkle checks and permission status had no central owner. | Exact dependency pins, PermissionService, OnboardingCoordinator, UpdaterService; no automatic permission prompt, auto-download or install. | Three permission/onboarding tests plus real installed guide navigation. |
| Medium | Decorative motion ignored Reduce Motion; render tests depended on host preferences. | Disable floating, hints, star animation and contact particles for Reduce Motion. Make contact fixture preference explicit. | Full suite passes with host Reduce Motion enabled. |
| Low | Monolithic simulator/catalog files mixed UI, control and cache responsibilities. | Separate SimulatorView, SimulatorModel, SimulatorAdapters and AppleModelCache. | Build and unchanged interaction/render regressions. |
| Low | Obsolete copied SwiftPM bundles/resources could leak into incremental packaging. | Copy an explicit bundle allowlist and reject excluded wallpapers/models/credentials. | Packaged resource audit, including the failure that originally caught the obsolete bundle. |
| Low | New macOS 27 audio API references prevented compiling with the documented Swift 6.2 SDK toolchain. | Compiler-gate the new API spelling; keep the earlier runtime path. | Swift 6.4 build passes. CI is configured for macOS 26; remote CI has not run yet. |

Review covered the Swift targets, Metal shader, tests and packaging/download
scripts: queue ownership, cancellation, sensor filtering, lock/sleep handling,
resource lifetime, GPU upload/draw ordering, cursor balance, model verification,
audio scheduling, input adapters, localization and distribution. Runtime claims
below are limited to the evidence actually collected.

## Implemented product/release work

Three-step English/Dutch onboarding offers a shared interactive demo, explicit
Screen Recording request or skip, and current permission/sensor status. Settings
can reopen the guide. Re-entering the app refreshes system permission immediately;
stored onboarding completion never grants access. Production excludes experimental
lock-screen code. PermissionFlow 2.11.2 and Sparkle 2.9.6 are pinned in
`Package.resolved`; only the screen-recording status extension is linked.

Original icon, MIT license, third-party credits and terms, privacy explanation,
English README, asset inventory, release scripts and public-safe CI are present.
The responsive GitHub Pages site includes a real example-image screenshot and a
working Homebrew copy button. Final download metadata is generated from the signed, notarized, stapled DMG.
The public download URL remains unpublished until the remaining gates pass.

## Verified locally

- **94 XCTest tests passed, zero failures and zero skipped tests**: 26 core,
  19 graphics, 46 simulation, 3 permission/onboarding tests. The official asset
  tests were enabled with `DUO_APPLE_MODELS` (12 source assets, 16 configurations,
  48 angle images and contact frames). Evidence: ignored local test logs and
  `build/verification/` images.
- English/Dutch app keys and formatting match: 111 strings, plus all 22
  PermissionFlow strings. Bundle lookup verifies the packaged Dutch supplement.
- Clean arm64 optimized build, minimum-load-command 14.2, framework symlinks and
  runtime search path, Developer ID team N2982AVX2Z, hardened runtime and secure
  timestamp; signatures validate strictly throughout the app.
- The RC DMG mounts and contains an Applications link. Its app was copied into
  `/Applications/Magic Hinge.app`; installed executable SHA-256 matches the
  verified candidate. The installed app launches outside the checkout. The Dutch
  guide's three steps, headings, labels and buttons were inspected via AX and
  navigated through “Gebruik alleen de simulator”. English UI also inspected.
- The installed app also launched with a process-local `sandbox-exec` network
  deny policy. The cached official model and built-in example rendered; no
  network access was available to that process. Offline screenshot inspected.
- The website was checked at 1440 px desktop and 390 px mobile, light/dark,
  without horizontal overflow. Homebrew copy writes the exact command. All local
  page resources resolve. Screenshot contents were inspected: only the built-in
  example image, no personal desktop content.
- Source audit finds no private-key/token patterns, personal absolute paths,
  builds, cached models or generated release artifacts among commit candidates.

## Size and asset outcome

The [asset inventory](asset-inventory.json) records size, resolution, hash, use
and terms. Original wallpaper resolution, meshes and textures are retained.

- Previous app: 31.3 MiB on disk; current signed app: approximately **27.0 MiB**,
  including approximately **3.0 MiB** for Sparkle.
- Final signed, notarized and stapled DMG: **25,625,996 bytes (24.4 MiB)**.
  SHA-256: `4c9abe541449bc8c8a9b2385845d35e1be080c2c87f8003bc40ed1baacba7247`.
- All official model fixtures including color layers: approximately **87.3 MiB**.
  Normal per-user cache size depends on the models actually requested.
- Excluding unused `DuoNight.jpg` removes 10,138,610 bytes (about 9.7 MiB); it
  remains a development-only source asset.
- `jpegtran -copy all -optimize` preserved decoded RGBA content but increased
  DuoDay from 10,196,715 to 10,694,927 bytes and starless night from 8,903,497 to
  9,331,206 bytes. Both optimizations were rejected; original files are unchanged.

## Release gates still open — do not publish

1. **Passed:** local `magic-hinge` Keychain authentication, app and DMG notarization,
   stapling, strict signatures and Gatekeeper. App submission
   `84f8d30c-56a4-4b0a-936e-c05c97cc4a3d`; DMG submission
   `1afdbc34-7bd6-4bf8-93fd-c7b72420eea0`. Apple logs retained locally.
   The app installed from this DMG also passes Gatekeeper and stapling.
2. The new Sparkle key is generated in Keychain and its public key is embedded.
   The isolated internal update fixtures are signed with Developer ID. EdDSA
   signatures verify and reject a corrupted archive. The in-app 100 → 101
   installation/relaunch succeeded; an in-app corrupted update was rejected
   with “The update is improperly signed and could not be validated.”
   **Passed:** notarized/stapled builds 200 → 201 installed and relaunched;
   the isolated preference sentinel survived. Gatekeeper and stapling pass on
   the updated app. A corrupted archive was rejected in-app with the same
   signature error, leaving build 201 installed. Evidence: local
   `build/update-notarized/signature-test.json` and `corrupt-update-ui.txt`.
   The loopback feed isolates this test; public HTTPS delivery is still pending.
3. A **macOS 14.2 runtime machine/VM** has not been supplied. This is an explicit
   release blocker, not an optional check.
4. The owner's physical opening/closing, stillness, sleep/wake, clamshell and
   emergency-stop test is pending against the final notarized candidate.
5. Full real permission denial/revocation/restart matrix and spoken VoiceOver
   checks remain pending; injected unit tests and AX labels are not equivalent.
6. Public GitHub repository/tag/release, live Pages/appcast and Homebrew tap
   mutation are intentionally deferred until the preceding gates pass. Remote CI,
   Homebrew install/upgrade/uninstall and the re-downloaded artifact's Gatekeeper
   check therefore remain pending.

Current `spctl --assess` result for the app, installed app and DMG:
**accepted — Notarized Developer ID**. No
quarantine attribute or system security policy was removed to conceal this.
