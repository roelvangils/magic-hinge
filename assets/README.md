# Magic Hinge icon

`Magic Hinge.icon` is the editable Icon Composer source. The user-supplied folded
silhouette is rendered as cyan/lilac glass, with a pearlescent rim and a short,
rounded center bar of equal stroke width. The original vector is preserved in
`icon-source/05-folded-glass.svg` and copied into the document's Assets folder.

`AppIcon.png` and `AppIcon-Dark.png` are the 1024px native Default/Dark exports.
Run `scripts/export-composer-icon.sh` to regenerate previews. Website exports
are 256px and follow the website appearance setting, including the favicon.

`scripts/make-icon.sh` compiles the native document with actool. The application
bundles Assets.car with Aqua and DarkAqua icon stacks, plus the generated ICNS
fallback for older macOS versions. The DMG uses that ICNS as its volume icon.
The app's bundle identifier and preferences remain unchanged.

Building the icon requires Xcode 27 or later, matching the Icon Composer source.
CI uses the `xcode-27` runner; this does not change the macOS 14.2 app target.
