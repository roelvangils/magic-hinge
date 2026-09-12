# Procedural night sky

Implemented in version 2.1.3 (29), in `Sources/DuoGraphics/ProceduralStars.swift` and connected to `AppearanceWallpaper`.

Source: the supplied `DuoNightNoStars.jpg`, copied unchanged as `Sources/MagicHinge/Resources/DuoNightStarless.jpg` and included in the executable's resources. Size: 6016 × 3900; the horizon matches the previous wallpaper. Source and bundled SHA-256: `050a22dbb0a396041d8706ba1823d0e2f4024a50fd2f9486921a53d49a93b085`.

The starless wallpaper and procedural layer now replace the previous night image. The app keeps the existing 0.36-second blur/crossfade. Light appearance excludes the night layer; Auto follows effective system appearance.

165 seeded stars have stable image-space positions, varied size/brightness, independent phases, and periods from 2.8 to 7 seconds (increased shimmer in 2.1.4). Two smooth harmonics change opacity with stronger contrast and slightly larger bright stars, without blinking out. A cached radial sprite gives soft subpixel edges. The same aspect-fill transform as the wallpaper keeps the stars above the mountains when resizing.

Core Animation animates opacity without a SwiftUI frame timer or continuous wallpaper decoding. The sky clock pauses when inactive, detached, hidden or fully occluded, and resumes from its paused time. The layer is part of the night wallpaper's opacity/blur transition. No extra setting or interface control is added.

Four `ProceduralStarsTests` pass: stable sky coordinates, continuous bounded shimmer, pause/resume and non-intercepting input, plus a rendered sky at `build/verification/procedural-stars.png`. The rendered test composition uses the supplied night image; its horizon and star placement have been visually inspected. The new night composition and About window were also verified in the running 2.1.3 app.

Apple occlusion documentation: https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification


## Shooting stars (2.1.5)

`ShootingStar.swift` creates seven varied paths and staggered timings on a repeating sky-local schedule. The first streak arrives after 8–14 seconds of active sky time, with subsequent starts 24–42 seconds apart. Every streak lasts 0.65–0.95 seconds. A cached, tapered sprite gives a bright head and soft fading tail; opacity and position are composited by Core Animation.

The shooting-star container inherits the existing sky clock, including pause/resume, dark-mode crossfade and occlusion handling. No timers or per-frame SwiftUI updates are added. Paths are constrained to the visible part of the sky above the mountain ridge. Relayout retains the schedule epoch.

Seven focused sky tests pass, including non-overlap across the repeat boundary, bounds at different window sizes, and shared pause behavior. The composited still is `build/verification/shooting-star.png`.
