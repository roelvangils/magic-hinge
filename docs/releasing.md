# Local release operations

`release.json` is the only version/build/architecture/feed/key source.
`Package.resolved` pins dependencies. The public repository is
`roelvangils/magic-hinge`; production signing stays on the maintainer's Mac.
Do not publish until every gate in `release-review.md` has evidence.

## Prepare and test

1. Run `scripts/verify-release-local.sh`. All 16 configurations must load and
   produce the 48 angle renders plus the contact-effect fixtures. A skipped
   official-asset test is not a release pass. Inspect closed Air and native-joint
   variants; image existence is not visual correctness.
2. Inspect English/Dutch, light/dark, keyboard focus, VoiceOver, no permission,
   granted permission, denial, revocation, skip, resume, and macOS-required restart.
3. Build `scripts/build-app.sh distribution`. This creates a clean arm64 build,
   signs nested Sparkle code inside-out with hardened runtime/timestamps, retains
   framework symlinks, and verifies bundle identity/resources/rpath/deployment.
4. Install and run the candidate on **macOS 14.2**. A deployment-target check or a
   test on a newer OS does not satisfy this gate.

The distribution script uses the standard Developer ID trust requirement. The
old manual identifier-only designated requirement is no longer used.
Development builds are ad-hoc and do not start the production updater.
PermissionFlow's separately maintained Dutch strings are overlaid into its
resource bundle before signing. Compare all keys and printf placeholders during
localization checks. Upstream source is not modified.

## Local credentials

The Developer ID Application certificate for team N2982AVX2Z must be in Keychain.
Configure notarytool once in your own Terminal:

```sh
xcrun notarytool store-credentials magic-hinge --apple-id roel@elevenways.be --team-id N2982AVX2Z
```

Enter the app-specific password at the hidden prompt. Never put it in a command,
chat, environment dump, source file or CI secret. Signing keys remain in Keychain:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account magic-hinge
```

Only its public key belongs in `release.json`. Back up signing keys using the
maintainer's own secure procedure; do not export them into the repository.

## Notarize and freeze the download

```sh
scripts/notarize-release.sh
```

The script zips the signed app, submits and waits, saves submission IDs and full
Apple logs under ignored `build/notarization`, requires Accepted, staples the app
and checks Gatekeeper. Then it creates an Applications-link DMG with the original
icon, signs/notarizes/staples the DMG, and generates the checksum and EdDSA signature.
A rejected submission stops the procedure and preserves its report. Existing final
DMGs are never silently overwritten.

`release-metadata.py` generates all these together from the final download:
`SHA256SUMS`, `release-final.json`, `website/release.json`, `website/appcast.xml`,
and `magic-hinge.rb`. Never modify the DMG after this step. Each changed binary
requires a new signing/notarization cycle and regenerated metadata.

## Physical and update gates

The owner tests opening, closing, stillness, sleep/wake, clamshell and emergency
stop on the candidate. Record the build and result in the release report.

Perform an actual Sparkle installation between two separately signed internal
builds with increasing CFBundleVersion and a private test feed. Verify that the
new app relaunches with existing preferences. Corrupt a COPY of the signed DMG
and confirm rejection both by `sign_update --verify` and by the in-app update
flow. Signature verification alone does not satisfy the end-to-end update gate.
Do not point the production feed at temporary or mutable test files.

Test DMG installation into Applications, a launch outside the checkout, and an
offline relaunch with cached models. Re-download the uploaded DMG and rerun SHA-256,
`codesign --verify`, `xcrun stapler validate` and `spctl` on that download/mounted app.

## Publish after every gate passes

1. Run `scripts/check-source.py`; inspect the source image inventory for private
   desktop content. Commit source, lockfile, tests, licenses, docs, scripts and
   website. Exclude builds, model caches and test images.
2. Create the public GitHub repository, push main and immutable tag `v2.3.0`.
   Publish the matching DMG and SHA256SUMS with the reviewed release notes.
3. Enable Actions-based Pages; publish `website/` with the included workflow.
   It refuses deployment until final appcast and download metadata exist.
4. Add the generated cask to `Casks/magic-hinge.rb` in `roelvangils/homebrew-tap`.
   Test `brew install --cask roelvangils/tap/magic-hinge`, upgrade between the
   internal versions and uninstall. Never run `--zap` or erase user preferences.
5. Verify the live page, feed, download signature, checksum, and installation
   command. Update the README preparation status only when these checks pass.

Official references: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Sparkle](https://sparkle-project.org/documentation/),
[PermissionFlow](https://github.com/jaywcjlove/PermissionFlow),
[Homebrew Cask](https://docs.brew.sh/Cask-Cookbook),
[GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
