# Optional crash reporting

Magic Hinge uses the pinned Sentry Cocoa 9.28.0 static SDK. Only the main app
depends on it; the renderer and frame generator do not. The SDK starts only when
the user enables **Send crash reports** in General settings and a valid HTTPS DSN
is present. The setting is off by default. Disabling it closes the SDK and the
before-send guard drops events after consent is withdrawn.

The integration disables session tracking, automatic performance tracing, network
instrumentation, app-hang monitoring, breadcrumbs, logs, metrics and memory
introspection. It does not attach screenshots or UI hierarchies; these SDK features
are not available for this macOS target. The app never adds file attachments.
Events retain crash stack traces, technical device/OS context and release/build
identifiers, but user identity, persistent device IDs, locale/timezone context,
requests, extra values and breadcrumbs are removed. The project enables server-side
IP scrubbing and uses the organization’s EU data region.

## Configuration

Set the public ingestion DSN as `sentryDsn` in `release.json`, or override it with
the `SENTRY_DSN` build environment variable. It is written into the app's Info.plist.
A DSN is public client configuration, not an administrative auth token. Without a
DSN the SDK remains off and the settings toggle is hidden.

Distribution builds use `production`, local builds use `development`. Release IDs
are `bundleIdentifier@version+build`; the distribution identifier is the build
number. Do not reuse a published version/build for a new binary.

## Verification

Run `swift test --filter CrashReportingTests` for consent lifecycle, missing DSN
and event redaction. Tests use injected SDK calls and send nothing.

Build a configured development app and run:

```sh
"build/Magic Hinge.app/Contents/MacOS/MagicHinge" --sentry-smoke-test
```

This explicit debug-only command sends one fixed test message in the
`integration-test` environment and prints its event ID. It does not capture the
desktop or change the user's crash-reporting preference. Verify that ID in the
Sentry project; a local flush alone does not prove server ingestion.
This smoke test checks delivery, not an actual crash/relaunch.

## Release symbols

The bundle assembler preserves the SDK's privacy manifest and generates the
release binary's dSYM under `build/symbols/<Mach-O UUID>/MagicHinge.dSYM`.
Keep these private build artifacts outside the app and GitHub release assets.
Upload the matching dSYM before publishing the binary:

```sh
scripts/upload-sentry-symbols.sh build/symbols/UUID/MagicHinge.dSYM
```

Authenticate Sentry CLI locally, or supply `SENTRY_AUTH_TOKEN` through a secret
environment variable. Never put the token into chat, command arguments or Git.
The default organization/project are `eleven-ways` and `magic-hinge`; the script
accepts environment overrides. It does not upload source files. Verify the binary
UUID with `xcrun dwarfdump --uuid` and confirm the uploaded debug file in Sentry.

SDK documentation: https://docs.sentry.io/platforms/apple/guides/macos/

## Integration verification

Project `magic-hinge` (4512079439331408) was created in Eleven Ways on 2026-09-13.
The SDK smoke event `3e484b9f71e2422d8db507c8d1aac02f` was sent in the
`integration-test` environment; its matching dSYM was uploaded and processed before sending.
The local release build and bundle signature/resource checks passed. The public
0.9.1 download is unchanged; a new signed/notarized release is required to ship
this integration to users.
