# Magic Hinge 0.9 Beta

The first public beta of a completely unnecessary upgrade to opening your laptop.
Magic Hinge brings a glass-like screen animation to your MacBook, with an
interactive simulator when a compatible hinge sensor is unavailable.

- Free and open source; English and Dutch interface.
- Apple silicon. macOS 14.2 is the minimum deployment target.
- Developer ID signed and notarized; download the DMG and drag the app to Applications.
- Screen Recording is optional. Desktop images stay in memory, never saved or uploaded.
- Install through Homebrew: `brew install --cask roelvangils/tap/magic-hinge`.

This is **beta software**, not a stable release. Testing on macOS 14.2 itself,
the complete physical hinge/sleep/clamshell matrix, permission revocation/restart
flows and spoken VoiceOver checks remain pending. Sensor availability is detected
at runtime. Please report bugs with your Mac model, macOS version and steps to
reproduce; do not attach private desktop screenshots.

Internal bundle version: 0.9.0 (39). Existing preferences and model cache are retained.
