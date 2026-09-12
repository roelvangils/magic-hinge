# Onderzoek — 11 september 2026

## Versie 1.1: beweging, terugkeer en hogere framerate

De gebruiker bevestigde dat het effect van 1.0 na de backing-layercorrectie werkt en vroeg daarna om directe activering in beide richtingen, een terugkeer na één seconde rust, meer blur en een veel donkerdere bovenzijde. Versie 1.1 vervangt daarom de vaste beginhoek door relatieve bewegingsdetectie. Een bevestigde HID-stap (circa één graad) activeert het effect. Na één seconde zonder nieuwe stap volgt een quintic-easing naar nul in 0,45 seconde. De nieuwe ruststand is meteen het volgende referentiepunt. Hervatten tijdens de terugkeer behoudt de zichtbare vervorming.

De HID-polling is verhoogd naar 120 Hz. [NSView.displayLink](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)) stuurt de zichtbare animatie los van die sensorevents aan, op maximaal 120 Hz. De capturefilter wordt vooraf klaargezet; [SCScreenshotManager.captureSampleBuffer](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturesamplebuffer(contentfilter:configuration:completionhandler:)) levert een pixelbuffer die via CVMetalTextureCache direct door Metal wordt gelezen. Het wegvallen van de CGImage-/CPU-kopie is met een kleur- en oriëntatietest gecontroleerd. De live logs registreerden circa 119–120 gepresenteerde fps na de laatste optimalisatie en 48–56 ms capturetijd na de eerste opname, op 3024×1964. Dit is geen framerategarantie.

De standaardsigma is verdubbeld van 0,055 naar 0,11 schermhoogte. De schaduw gebruikt nu `max(0, 1 - 2.6 * darkness * abs(gap)^0.8)^2`: helder bij het scharnier en donker aan de bovenzijde. Na visuele feedback is darkness van 0,86 naar 0,66 verlaagd. De geometrie gebruikt de absolute kantelhoek zodat ook naar buiten bewegen alleen versmalt en nooit breder wordt dan de ruststand. Perspectief is gescheiden van de blur, zodat de perspectiefschuif de vervaging niet uitschakelt.

De cursoroptie balanceert één CGDisplayHideCursor met één CGDisplayShowCursor; cleanup bij fouten, pauzeren, slaap en afsluiten herstelt die aanvraag. Openen vanuit slaap kan al deels voorbij zijn voordat een app opnieuw draait. De openingsoptie gebruikt daarom een korte beginvervorming als het deksel tijdens slaap bewoog en hervat daarna de gewone bewegingscyclus. Een fysieke slaap/ontgrendeltest blijft nodig voor het precieze moment op deze macOS-versie.

Apple documenteert [canBecomeVisibleWithoutLogin](https://developer.apple.com/documentation/appkit/nswindow/canbecomevisiblewithoutlogin), maar die venstervlag geeft op zichzelf geen toegang tot beveiligde loginbeelden. Apple beschrijft pre-loginvensters in de context van [authorization plug-ins](https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins), een andere integratie dan deze gebruikersapp. Er is geen betrouwbaar werkend volledig-login-effect aangetoond. Daarom is de loginoptie zichtbaar maar uitgeschakeld. De app wist de overlay bij vergrendeling en hervat na ontgrendelen; er wordt geen oude desktop boven een loginvenster getoond.

### Aanpassing 1.1.1: sensorruis en interpolatie

Iedere onbewerkte omkering van één graad werd eerst als echte beweging behandeld. Daardoor kon ruis rond een hoekgrens het effect veranderen of de rusttimer herstarten. Een mediaan van drie metingen onderdrukt losse uitschieters; een stap van één graad wordt na 40 ms bevestigd, een kleine omkering na 100 ms. Grotere bewegingen blijven snel volgen. De displaylus gebruikt nu exact geïntegreerde kritische demping (tijdconstante 20 ms) met doorlopende positie en snelheid, in plaats van de eerste-orde-interpolatie van 16 ms. Oude timestamps mogen de animatieklok niet terugzetten. Synthetische traces testen stilstand met ruis, echte trage beweging, snelle omkering en tussenframes op 60/120 Hz. Fysieke validatie blijft nodig om te bepalen of dit de door de gebruiker waargenomen flikkering volledig verhelpt.

De volgende secties leggen het oorspronkelijke onderzoek en de implementatie van versie 1.0 vast; de genoemde vaste beginhoek en CPU-afbeeldingsroute zijn in 1.1 vervangen.

## Wat het effect doet

De aangeleverde afbeelding laat een ruimtelijk variërende vervaging zien: de wegkantelende helft vervaagt en verdonkert sterker aan de buitenrand. Alleen een uniforme blur of een simpele 3D-rotatie van een screenshot geeft niet dezelfde indruk.

De primaire ontwikkelaarsbron [DuoLikeAnimation](https://github.com/elijah-semyonov/DuoLikeAnimation) modelleert de interface als een stilstaand vlak, bekeken door een kantelende matglazen ruit. De kijker blijft op een vaste positie. Een straal van het oog door elk punt van de bewegende ruit bepaalt welk deel van de oorspronkelijke interface daar zichtbaar is. De afstand tussen ruit en interface bepaalt de vervaging en lichtabsorptie. Dat is een reconstructie, geen vrijgegeven Apple-implementatie.

Ook [de Three.js-studie van chuspeeism](https://github.com/chuspeeism/iphone-duo) gebruikt vaste frontale projectie en progressieve blur. De verschillende reconstructies verschillen in kijkafstand, afsnijding en verduistering. Er is dus geen publiek bevestigde exacte Apple-curve om letterlijk over te nemen.

[Apple's aankondiging](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/) bevestigt dat content reageert op het vouwen, maar specificeert de shader en hoekcurves niet. De introductie was op 9 september; de aangekondigde winkelbeschikbaarheid is later. Voor dit project gebruiken we de getoonde animatie als visuele referentie.

## Vertaling naar een MacBook

Dit zijn onze ontwerpkeuzes, niet beweringen over Apple's interne code:

- Het vaste scharnier ligt onderaan. De volledige laptopdisplay is één bewegende ruit.
- Het oorspronkelijke bureaublad ligt op het vlak van de ingestelde beginhoek.
- Een oog op 2,4 schermhoogtes afstand kijkt naar het midden van dat vlak.
- Verandering van de echte scharnierhoek bepaalt de virtuele kanteling; er loopt geen tijdanimatie bij gewoon gebruik.
- De onscherpte neemt continu toe naar boven en bij verder sluiten. Buiten de geprojecteerde beeldranden wordt zwart getoond.
- Tijdens de laatste 12% van de sluitbeweging gaat het scherm geleidelijk naar zwart. macOS mag daarna normaal slapen.
- Er is geen tweede fysiek display aan de achterkant van de MacBook. De overgang naar het buitenscherm van een iPhone kan dus niet letterlijk worden gereproduceerd.

Met genormaliseerde coördinaten `x, y` (bovenaan `y=0`) is `d=1-y` de afstand tot het scharnier. Voor kanteling `a` wordt het glaspunt `G=(x, 1-d*cos(a), d*sin(a))`. Het oog is `E=(0.5,0.5,D)`. De straal snijdt het oorspronkelijke vlak op `E.xy + (G.xy-E.xy)*D/(D-G.z)`. De onderrand blijft daardoor exact vast. De voorspelde illusie is het sterkst bij de gekozen kijkpositie; er is geen oogtracking.

De shader gebruikt een Gaussian-piramide. Die wordt eenmalig uit een sRGB-schermopname opgebouwd in lineaire RGBA16Float-texturen. Per pixel wordt daarna continu tussen vervagingsniveaus geïnterpoleerd. Dit vermijdt een grote blur-kernel voor ieder pixel in ieder frame. Output gaat terug naar een expliciete sRGB-drawable.

## Scharniersensor

De primaire bron is [Sam Henri Golds LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor), de app met het krakende deurengeluid. Het relevante interfacepad is publieke IOKit/IOHID-functionaliteit met een ongedocumenteerd Apple-sensorprotocol, geen ingelinkte private framework.

Het protocol: Apple vendor `0x05AC`, product `0x8104`, usage page `0x20`, usage `0x8A`. HID feature report 1 bevat een report-ID gevolgd door een little-endian hoek in gehele graden. Alleen deze interface wordt geopend: andere sensoren delen hetzelfde product-ID. Niet ieder MacBook-model biedt dit interface aan; sensorfouten blijven expliciet zichtbaar.

De lokale probe vond een `las`-sensor op deze MacBook Pro (Mac17,7, Apple M5 Max). Gesloten werd 0° gemeten, bevestigd door de gebruiker. Na openen zijn onder meer 119°, 123° en 124° live gezien. De app leest op een aparte serial queue op 60 Hz, filtert met een tijdconstante van 28 ms en stopt het effect als actuele data ontbreekt.

Onderzochte commits:

- LidAngleSensor: `f7e4e5cb46fe13a518091ce5d47f0ec2e3fecd80`.
- DuoLikeAnimation: `0aa525639a494be8abdf4c4e1e25dcb52d372d94`.

## Schermopname en venster

[ScreenCaptureKit / SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) levert één afbeelding zodra de sluitdrempel wordt overschreden. Er is geen doorlopende desktopvideo. Het overlayvenster wordt van de opname uitgesloten; de afbeelding wordt alleen in geheugen gehouden. Een generatie-token voorkomt dat een vertraagde capture alsnog verschijnt na openen of uitschakelen.

De SwiftUI-interface bedient een AppKit-panel met een [MTKView](https://developer.apple.com/documentation/metalkit/mtkview/). Het panel neemt geen focus over, volgt Spaces en kan boven andere apps staan. Alleen het ingebouwde scherm wordt gekozen. Schermwissels, slaap en een inactieve gebruikerssessie verwijderen de overlay.

De eerste praktijktest ontdekte een presentatieprobleem dat de losse shader-tests niet konden vinden: een op nulformaat aangemaakt overlay had `CAMetalLayer.contentsScale = 0`, hoewel Metal geldige frames afleverde. De gecorrigeerde versie maakt een venster met werkelijk formaat, activeert backing layers en stelt de actuele Retina-schaal expliciet in. De diagnose bevestigde daarna schaal 2, een 3024×1964-drawable en voltooide GPU-commando's.

## Grenzen van de verificatie

Tien automatische tests controleren het HID-formaat, de activatiecyclus, de hysterese, sensorverlies, smoothing, de vaste scharnierlijn, kleurechtheid bij nul kanteling, volledige verduistering en de sterkere blur bovenaan en een geldige backing layer voor het standalone Metal-venster. De GPU-tests renderen de werkelijke Metal-shader en exporteren voorbeeldframes. Een losse 3456×2234-GPU-render duurde rond 0,14 ms; dit sluit opname-, upload-, compositor- en sensorlatentie uit en is geen garantie voor end-to-end framerate.

Schermopname en GPU-rendering van de echte desktop zijn afzonderlijk getest met niet-zwarte uitvoer. De exacte perceptuele overeenkomst met een fysieke iPhone Duo is niet gemeten. HDR wordt voor deze SDR-overlay omgezet naar sRGB. Beveiligde videoinhoud kan door macOS uit de opname worden weggelaten. De mouse cursor blijft een afzonderlijke macOS-laag. De app houdt de Mac niet wakker en omzeilt het vergrendelscherm niet.

### Fysieke scharniertest na 1.1.1

De nieuwe opname bevat 11.308 sensorwaarden, van 130° tot 4° en weer terug. De uiteindelijke 129° bleef ruim 20 seconden constant; de GUI stond daarna correct op Klaar. De mediane meetafstand was 8,3 ms; één onderbreking duurde circa 127 ms. Er waren kleine omkeringen bij de maximale openingshoek, geen grote losse uitschieters. De gepresenteerde framerate varieerde bij deze test met het livevoorbeeld ingeschakeld circa 93–115 fps. De eerdere 119–120 fps is dus geen constante praktijkwaarde. Traces en samenvatting staan lokaal onder `build/verification/hinge-test/`. De CLI-segmenten herstarten hun diagnostische bewegingsmodel op de minuutgrens; de GUI bleef doorlopen. Visuele feedback van de gebruiker is nog nodig om de resterende flikkering te beoordelen.

### Snellere terugkeer na stilstand

Na verdere gebruikersfeedback is de rustvertraging verkort van 1,0 naar 0,4 seconde. De omgekeerde animatie duurt nog steeds 0,45 seconde: circa 0,85 seconde na de laatste bevestigde beweging is het gewone bureaublad terug. De eerdere testbeschrijvingen hierboven horen bij de toenmalige vertraging van één seconde.

### Energie en vergrendelscherm: experimentele controle

De sensor pollt nu op 30 Hz in rust en schakelt na de eerste ruwe hoekwijziging naar 120 Hz tot één seconde na de laatste wijziging. Tijdens vergrendeling stopt hij. Dit vermindert het aantal rustmetingen met 75%, zonder een claim over gemeten batterijduur. Low Power Mode begrenst de display link op 60 Hz. Het onzichtbare Metal-voorbeeld tekent niet tijdens de overlay; identieke overlaystanden worden niet opnieuw getekend.

De nieuwe vergrendeltest gebruikt uitsluitend de publieke venstervlag `canBecomeVisibleWithoutLogin`, een vensterniveau boven `CGShieldingWindowLevel()` en `NSVisualEffectView` met behind-window blending. Apple documenteert dat die blending inhoud achter het venster gebruikt: https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow . De test wacht maximaal twee minuten op vergrendelen, toont een klein klikdoorlatend kader maximaal 15 seconden, en ruimt daarna op. Er is geen screenshot, geen toegang tot wachtwoorden en geen authenticatie-integratie. Zichtbaarheid en daadwerkelijke blur moeten nog op deze Mac bevestigd worden. Zelfs een geslaagde blurtest bewijst geen volledige Metal-perspectiefvervorming van het beveiligde scherm.

### Natuurlijker bewegingsmodel

Verder openen vanuit rust start geen nieuwe vervorming meer. Sluiten bouwt een positieve vouw op, en heropenen vermindert die vouw tot nul zonder naar een omgekeerd effect door te schieten. Zodra het beeld weer vlak is, wordt de opname vrijgegeven. Ontwaken met een bijna gesloten deksel gebruikt een positieve onthulling die afneemt naar nul bij 45 graden. Als het deksel bij de eerste beschikbare meting al verder open is, wordt de openingsanimatie overgeslagen. De 45-gradenregel veroorzaakt daardoor geen zichtbare sprong in een lopende animatie.

### Interactieve 3D-simulator

Een apart SwiftUI-venster bevat een SceneKit-model van een MacBook Pro, met een fysiek scharnier van 0–130 graden en een verticale NSSlider. Het model is in code opgebouwd; het betreft geen Apple-CAD-bestand. Afzonderlijke toetsen, speakerroosters, poorten, trackpad, afgeronde platen, rubbervoeten en de camerauitsparing zijn aanwezig. PBR-materialen worden verlicht met Poly Havens CC0 Studio Small 09 HDRI.

De virtuele scherminhoud komt uit dezelfde FoldRenderer als de werkelijke overlay. De nieuwe `renderTexture`-route levert een private MTLTexture zonder CPU-readback; SceneKit accepteert deze als materiaalinhoud, zoals Apple documenteert: https://developer.apple.com/documentation/scenekit/scnmaterialproperty/contents . Een GPU-regressietest vergelijkt deze uitvoer pixel voor pixel met de bestaande offscreenroute. Een tweede test controleert de fysieke scharniertransformatie en exporteert studioaanzichten bij 0°, 45°, 110° en 130°. In de draaiende app zijn de verticale schuif, sluitvervorming en herstel na stilstand gecontroleerd.

De simulator tekent op verzoek, tot 60 updates per seconde tijdens beweging (30 in Low Power Mode), en stopt zijn animatietaak wanneer het model stil is of het venster niet actief is. De directe bureaubladoptie maakt alleen op verzoek een opname in het geheugen.
