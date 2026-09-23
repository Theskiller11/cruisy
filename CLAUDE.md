# Cruisy

App iOS per chi è in crociera. Risponde a una domanda sola: **quanto manca?** In porto, al rientro
a bordo (*all aboard*). In mare, all'arrivo nel prossimo scalo. Di Matteo Papini, in italiano, iOS 26,
SwiftUI. Non ancora pubblicata.

Se riprendi il lavoro con un compito preciso, leggi anche `docs/handoff-fable.md`.

## Principi che non si toccano

Il design si può rifare da capo. Questi no, perché sono il motivo per cui l'app esiste.

- **L'orario pubblicato fa fede.** Il countdown viene dall'itinerario, mai da una stima. Ogni countdown
  dice da dove viene (`CountdownOrigin`: orario pubblicato, stima, correzione dell'utente). Una stima
  ottimistica è il modo più semplice di far perdere la nave a qualcuno. `ArrivalEstimate` esiste solo
  per **avvisare** quando l'andatura non torna, e non tocca il countdown.
- **Il cuore funziona senza rete.** Countdown, carta, itinerario, porti, navi e ora di bordo usano dati
  dentro l'app (`ports.bin`, `ships.bin`, `coastline.bin`). La rete serve solo a cose facoltative che
  degradano senza: meteo, foto, ricerca di navi, satellite.
- **L'ora è quella di bordo.** Ogni istante è in UTC; `ShipClock` è una scaletta di cambi alle 02:00
  (vedi `ShipClockSchedule.swift`). Gli orari che l'utente scrive sono **ora locale del porto**. Non
  usare mai `TimeZone.current` per mostrare un orario della crociera.
- **Accessibilità come pavimento.** Contrasto WCAG AA verificato dai test (`LiveryContrastTests`,
  in entrambe le modalità, `Contrast.swift`), Dynamic Type (niente dimensioni fisse per il testo; `@ScaledMetric` solo sulle
  altezze), VoiceOver, Riduci movimento (`Motion.honouring`).
- **Privacy.** La posizione non esce dal telefono. Nessun server nostro, nessuna statistica. Se aggiungi
  una chiamata di rete, aggiorna l'informativa: `docs/site/privacy.html`, pubblicata su
  https://cruisy.matteopapini.com/privacy (Cloudflare Pages, si ricarica a mano dalla cartella).

## Struttura

```
Cruisy/            app: viste (Views/), servizi (Services/), risorse
CruisyShared/      modello, carta, design — compilato sia nell'app sia nei widget
CruisyWidgets/     widget della schermata Home e Live Activity
CruisyTests/       test unitari, Swift Testing
CruisyUITests/     test di interfaccia, XCUITest: gesti della carta, apertura di ogni schermata
scripts/           test, screenshot, stringhe, costruzione dei database
docs/              sito (docs/site: home, privacy, assistenza), passaggio di consegne
store/             testi App Store e note per la revisione
figma/             script per il file Figma (piano Starter: 20 chiamate al mese)
```

Il progetto Xcode è **scritto a mano** (`objectVersion = 77`) con cartelle sincronizzate: un file nuovo
in una di queste cartelle entra da solo nel target, senza toccare il `.pbxproj`. `CruisyShared/` sta nei
gruppi sincronizzati sia dell'app sia dei widget.

Design di oggi — il biglietto d'imbarco, direzione D del 14 settembre 2026: `CruisyShared/Design/`
(`Livery` coi token chiaro/scuro e il catalogo delle livree, `TicketType`, `Ticket` coi componenti,
`SeaScene`, `Motion`, `Contrast`). Le regole per usarlo con coerenza sono in `docs/fable-report.md`,
sezione «Regole del sistema». Il design vecchio (`Palette`, `Typography`, `GlassSurface`,
`DebugFlags`) è **cancellato** dal 19 settembre 2026: editor, importazione, riesame e onboarding
sono `Form` di sistema con la tinta della livrea. La carta nautica ha i suoi colori a parte
(`CruisyShared/Chart/ChartInk.swift`): sono convenzioni da carta, non cambiano con la compagnia.

## Comandi

```bash
scripts/test.sh unit                    # test unitari, meno di un minuto
scripts/test.sh ui                      # test di interfaccia, circa due minuti
scripts/test.sh all
scripts/test.sh ui NavigationSmokeUITests/testAllPortsOpens   # uno solo

scripts/screenshots.sh                  # fotografa tutte le schermate → screenshots/<data>/foglio.jpg
scripts/screenshots.sh --lang en --size AX5 --only oggi-porto,diario
scripts/screenshots.sh --appearance dark  # modalità scura

scripts/sync-strings.sh                 # porta le stringhe nuove nel catalogo (xcodebuild non lo fa)
```

Simulatore: **iPhone 17 Pro**, iOS 27. Xcode 27.1 non lo crea più da sé: se sparisce,
`xcrun simctl create "iPhone 17 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
com.apple.CoreSimulator.SimRuntime.iOS-27-0`. Il tipo **iPhone Duo** c'è già; manca il sistema
27.1, e con quello arriva l'ottimizzazione per il pieghevole (regioni riservate, `onHingeChange`).

## Come si verifica, su questo Mac

- **Non c'è `Simulator.app`**, ma il simulatore **si tocca** col tool iOS Simulator di Claude Code
  (`tap`, `swipe`, `text`, `screenshot`, sull'«iPhone 17 Pro»): è così che si provano a mano gesti e
  sequenze, come lo strappo del biglietto nell'onboarding. `xcrun simctl` sa avviare e fotografare,
  non toccare. Per arrivare dritti a una schermata usa gli argomenti DEBUG:
  - `-sample inPort | atSea | beforeBoarding | farFromBoarding | imminent` — una crociera di prova;
  - `-tab oggi | itinerario | nave | diario`;
  - `-open carta | scalo | porti | editor | importazione | impostazioni | onboarding`
    (`Cruisy/Services/DebugLaunch.swift`);
  - `-onboardingStep 0…4`, insieme a `-open onboarding`, apre l'onboarding a un passo preciso;
  - `-cruisy.hasSeenDisclaimer YES` salta l'onboarding, `-AppleLanguages "(en)"` cambia lingua;
  - `-livrea rosso` veste l'app con una livrea del catalogo (`Livery.id`), perché la nave di prova
    non è nell'elenco e da sola resterebbe sempre quella di Cruisy;
  - `-ora 6.5` finge l'ora di bordo, per vedere la scena del giorno di mare all'alba, al tramonto
    e di notte.
  `scripts/screenshots.sh` li usa tutti (`--appearance dark` per la modalità scura). Guarda
  `foglio.jpg`, che le mette in griglia.
- **I gesti si verificano con i test di interfaccia**, non a occhio: `CruisyUITests/`.
- **Quando un test di interfaccia fallisce, il messaggio può mentire.** Esporta gli allegati e leggi
  l'albero dell'interfaccia al momento del fallimento:
  `xcrun xcresulttool export attachments --path <risultato>.xcresult --output-path <cartella>`.
  Il percorso del risultato lo stampa `scripts/test.sh`.
- **Un crash sul simulatore** lascia un rapporto in `~/Library/Logs/DiagnosticReports/Cruisy-*.ips`.
- `-sample deviceTest` (attivo nello schema per il telefono di Matteo) **scrive nell'archivio vero** e
  mette da parte la crociera reale; `-sampleRestore` la rimette.

## Trappole già pagate

- **Chiavi dell'Info.plist**: `INFOPLIST_KEY_…` funziona solo per un elenco chiuso di chiavi, e quelle
  fuori elenco vengono **ignorate in silenzio**. È così che è nato il crash col permesso «Sempre»:
  `UIBackgroundModes` non arrivava nell'app. Le chiavi fuori elenco vanno in `Cruisy-Info.plist`, e si
  verificano sull'**app compilata** (`/usr/libexec/PlistBuddy -c "Print :Chiave" <…>/Cruisy.app/Info.plist`),
  mai guardando il progetto. `InfoPlistTests` ne controlla alcune.
- **Concorrenza**: dal 14 settembre 2026 il progetto è in **Swift 6** con `SWIFT_APPROACHABLE_CONCURRENCY`.
  Un servizio `@Observable` con metodi `async` che modificano il suo stato è `@MainActor`: la schermata dei
  porti crashava perché più `load` modificavano lo stesso `Set` in parallelo. I delegati di CoreLocation e
  VisionKit passano da conformanze `@preconcurrency`; `SeaChart` è `@preconcurrency Animatable`; un valore
  preso da una proprietà dell'attore non si può passare ad ActivityKit (vedi `LiveActivityController.update`).
- **Immagini `.fill`**: mai come figlia diretta di uno stack. Detta la larghezza alla colonna e taglia i
  testi («Icon of the Seas» diventava «on of the Seas»). Si mettono in un `.overlay` su un `Color.clear`
  con altezza fissa.
- **Niente `.navigationTransition(.zoom)` verso schermate che usano il pinch**: quella transizione ha un
  proprio gesto di chiusura a pinch e SwiftUI non permette di spegnerlo.
- **Schermate a tutto schermo spinte in una scheda**: `.toolbar(.hidden, for: .tabBar)`, se no la barra
  delle schede resta sopra e un dito ci finisce.
- **Una vista senza gesti non ferma i gesti delle viste sotto.** Per lasciare lo swipe dal bordo al
  sistema sopra la carta c'è `BackSwipeEnabler`.
- **`Canvas` non anima niente da solo**: `withAnimation` su un valore letto da un `Canvas` produce uno
  scatto. La vista deve essere `Animatable` (vedi `SeaChart`).
- **Widget e Live Activity**: `Text(timerInterval:)` e `ProgressView(timerInterval:)` sono le uniche viste
  che si aggiornano da sole. Un `ProgressView(timerInterval:)` con `.frame(maxWidth: .infinity)` dentro un
  `GeometryReader` fa cadere il renderer della Dynamic Island.
- **Il catalogo delle stringhe** non si aggiorna con `xcodebuild`: dopo aver scritto testo nuovo lancia
  `scripts/sync-strings.sh`, traduci in inglese, e `LocalizationTests` controlla che non manchi niente e
  che le traduzioni tengano gli stessi segnaposto.
- **Dati di prova**: gli scenari `-sample` non scrivono il diario né la traccia su disco (`isDemo`), così
  non sporcano i dati veri. È voluto.

## Stile

- **Commenti in italiano**, che spiegano **perché**, non cosa. Quando una scelta nasce da un errore,
  scrivi l'errore: è il modo in cui il prossimo non lo rifà.
- Nomi dei tipi e delle funzioni in inglese, testo per l'utente in italiano, tradotto in `Localizable.xcstrings`.
- Test in Swift Testing (`@Suite`, `@Test`, `#expect`), con nomi che sono frasi.
- **Commit** in italiano, al presente, con questa riga in fondo:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` — o il modello che li scrive davvero.
- Mai `git push`, mai pubblicare niente, mai toccare il MeteoProxy sul TrueNAS senza che Matteo lo chieda.
