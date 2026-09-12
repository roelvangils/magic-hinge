# Original Apple product models

Retrieved and verified 11 September 2026. Original geometry, textures and materials are Apple content, not assets authored by this project and not covered by this project's code licensing. The USDZ files contain Apple copyright notices. They are downloaded into the user's local cache; no USDZ files are included in the app bundle or committed source. Public download availability is not an open-source licence or permission to redistribute the assets.

Primary sources:

- [Apple MacBook Pro](https://www.apple.com/macbook-pro/): 14-inch USDZ, including Silver and Space_Black variants.
- [Apple's 16-inch M3 Pro USDZ, space black](https://www.apple.com/105/media/us/macbook-pro/2023/232a2dbf-5898-4fd1-a350-6a7c5c2e31c9/ar/macbook_pro_m3_pro_16_space_black.usdz) and [silver](https://www.apple.com/105/media/us/macbook-pro/2023/232a2dbf-5898-4fd1-a350-6a7c5c2e31c9/ar/macbook_pro_m3_pro_16_silver.usdz). These are 2023 assets; the UI identifies that generation.
- [Apple MacBook Air](https://www.apple.com/macbook-air/): separate 13- and 15-inch assets for sky blue, silver, starlight and midnight.
- [Apple MacBook Neo](https://www.apple.com/macbook-neo/): one USDZ containing Silver, Blush, Citrus and Indigo variants, plus Open/Closed poses.
- [Apple website terms](https://www.apple.com/legal/internet-services/terms/site.html).

`Sources/DuoSimulation/Resources/AppleModels.json` records all 12 exact Apple-hosted URLs and verified SHA-256 hashes. The app composes colour variants locally without altering the original files. It rotates the display assembly about its physical hinge and replaces only the emissive screen material with the application's Metal output.

Model and size detection uses the local product name, not serial-number lookup. No enclosure-colour identifier was found on the tested Mac17,7; colour remains an explicit, saved user selection. Unsupported historical sizes do not claim automatic matching.
