# Native Anvil-effect — 12 september 2026

Geïmplementeerd in versie 2.1.0 (build 26), als eigen benadering van Keynotes Anvil-effect. Er is geen vooraf gerenderd filmpje nodig. In de onderzochte publieke Apple-documentatie is geen kant-en-klare Keynote Anvil-API gevonden.

## Uitvoering

- `AnvilBurstView` componeert 38 zachte stofpluimen en 24 kleine glinsteringen met transparante `CALayer`-sprites. Drie onregelmatige stoftexturen en één stertextuur worden vooraf in geheugen gemaakt. Deeltjes vertragen, groeien en vervagen; glinsteringen volgen korte ballistische banen.
- De simulator gebruikt zijn bestaande frameklok voor deterministische laagtransformaties en opacity, zonder impliciete animaties. Er is geen tweede timer en geen voortdurende emitter. Na maximaal 1,65 seconde verdwijnen alle deeltjeslagen; verbergen, modelwissel en ontkoppelen annuleren meteen. Een nieuwe sluiting vervangt een bestaande burst.
- Een afzonderlijke `LidClosureContact` triggert uitsluitend bij de werkelijk gerenderde 0°. De bestaande audiocontactdetectie behoudt haar voorsprong van 200 ms. Opstarten met een gesloten model geeft geen burst of geluid.
- `LidImpactResponse.strike()` geeft ook rustige sluitingen een korte gewichtsreactie; een sterkere handmatige klap wordt niet opgeteld bij deze minimumimpuls. De bestaande veer en schaduw reageren samen.
- `MacBookModel.contactEdgeBounds` gebruikt alleen de vaste behuizing. De ruime sleepzone bevat conservatieve begrenzingen van het gedraaide deksel en is daardoor ongeschikt voor deze visuele verankering. De onderrand wordt naar het transparante overlayvlak geprojecteerd. De overlay onderschept geen muis-/trackpadgebaren.

Dit is een eigen interactieve benadering, geen pixelidentieke kopie van Keynotes interne preset.

## Verificatie

24 gerichte tests slagen voor Anvil, sluitimpuls, zweven, toetsen, muis/trackpad en audio. De renderproef schrijft zes contactmomenten voor Pro 14, Pro 16, Air 13 en Neo 13 naar `build/verification/anvil/`. De plaatsing is visueel gecontroleerd; de burst is ook in de gebouwde app gezien. De bestaande Air 13-assetarticulatie toont bij 0° het toetsenbord boven het deksel; dit is eveneens zichtbaar in de oudere `build/verification/apple-models/air-13-midnight-0.png` en staat los van de particle-overlay.

```sh
DUO_APPLE_MODELS="$PWD/build/apple-models" swift test --filter 'AnvilEffectTests|LidImpactResponseTests|LidInteractionTests|LidKeyboardTests|LidSnapSoundTests|ClosedLidFloatTests'
```

## Onderzochte bouwstenen

`CAEmitterLayer`/`CAEmitterCell` zijn bruikbare alternatieven. Hier zijn losse, begrensde lagen gekozen zodat contactframes reproduceerbaar zijn en de simulator één klok behoudt.

- Apple: https://developer.apple.com/documentation/quartzcore/caemitterlayer
- Apple: https://developer.apple.com/documentation/quartzcore/caemittercell
- Apple: https://developer.apple.com/documentation/quartzcore/caspringanimation
- Apple Keynote: https://support.apple.com/guide/keynote/animate-objects-on-a-slide-tanf96d92cb6/mac
