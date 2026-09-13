# Privacy

Magic Hinge requests only Screen Recording access, when you press its permission
button. You can skip it and use the simulator's built-in example image.

The desktop effect takes a temporary screenshot and processes it on your Mac's
GPU. The simulator can refresh its desktop image when you return to the app.
Images stay in memory; the app does not save, upload, analyze or transmit them.
The effect clears on sleep, screen lock, permission loss and sensor errors.
The simulator discards captured textures on lock or permission loss.

The app reads hinge angle and your Mac's product name locally. It does not read
serial numbers, record keystrokes globally or request Accessibility, Input
Monitoring or Full Disk Access. Local keyboard shortcuts operate in app windows.

Model downloads connect directly to Apple's HTTPS servers. A pinned SHA-256
checksum verifies each file before use. Models are cached under
`~/Library/Caches/be.elevenways.MacBookDuo/AppleModels`; preferences use the same
existing bundle identifier. Once downloaded, models work offline. The built-in
procedural simulator works before a model is available.

Optional update checks fetch an appcast from GitHub Pages and updates from GitHub
Releases. These hosts and Apple receive standard network request information,
such as the IP address. Sparkle system profiling and automatic installation are
disabled.

The public website uses Matomo analytics hosted at `https://stats.11ways.be/`
to measure page views, downloads and outgoing links. Analytics cookies are
disabled, and the tracker respects browser Do Not Track settings. Matomo receives
standard request information, including the IP address and browser information,
as well as the page URL and referrer. Tracking runs only on the public Magic
Hinge website, not local previews. The website does not load remote fonts.
The Magic Hinge app contains no usage analytics. In builds configured for Sentry,
you can opt in to **Send crash reports** in General settings (off by default).
Crash reports include stack traces, app/build and macOS versions, and technical
device information. They go to the maintainer's Magic Hinge project on Sentry.
Sentry receives the IP address as part of the network connection; the SDK does
not explicitly include it or a user identity in the event. The project also
enables server-side IP scrubbing. Sentry may still derive an approximate location
from the connection. Persistent device identifiers and locale/timezone
context are removed before sending. No screenshots,
session replay, interaction breadcrumbs, performance traces or application logs
are collected by this integration. Reports may be cached locally and delivered
after the app restarts. Turning the setting off stops crash reporting; reports
already received by Sentry are not withdrawn.

Local diagnostic logs contain timings, dimensions, error messages and render
status. They contain no screenshot pixels. Development tests can export synthetic
renderings. Using `--example-image` disables desktop capture in the simulator for
privacy-safe demonstration screenshots.
