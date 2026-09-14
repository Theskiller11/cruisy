# Rapporto di Fable 5.1 — redesign «Biglietto d'imbarco» e revisione del backend

Scritto il 14 settembre 2026, nel worktree `worktree-agent-aa61746baf9e551b0` partito dal
commit `568927e`. Il lavoro è stato chiuso prima del previsto per il budget di Matteo: questo
rapporto dice cosa c'è, cosa manca, e **come continuare senza perdere coerenza** (sezione
«Regole del sistema», scritta per Claude Opus 5 o per chiunque riprenda).

## In breve

- **Backend**: Swift 6 con concorrenza stretta su tutti i target; `VoyageStore` diviso in
  `Preferences`, `LogbookStore`, `TrackRecorder`; livello di rete comune `NetworkClient`;
  cache delle foto fuori dal thread principale; profilo GPS a basso consumo per la
  registrazione; test di compatibilità dei formati su disco (che hanno trovato un difetto
  vero: la rotta registrata non finiva mai nel diario).
- **Design**: sistema di token nuovo (`Livery`, `TicketType`, componenti del biglietto,
  `SeaScene`) e schermate rifatte nella direzione D: Oggi in tutti gli stati, Itinerario,
  dettaglio dello scalo, Nave, Diario con i timbri a passaporto, Porti toccati, Carta.
- **Livrea per compagnia**: catalogo di 17 palette ispirate, agganciate a
  `ShipRecord.operatorName`, con il selettore nelle Impostazioni e la preferenza condivisa
  coi widget. Ogni token ha la variante **chiara e scura**, ricavata con il contrasto come
  vincolo; `LiveryContrastTests` scorre tutte le livree in entrambe le modalità. Per vedere
  una livrea con la nave di prova: `-livrea rosso` (o un altro `Livery.id`) fra gli
  argomenti di avvio.
- **Test**: 243 unitari (erano 214) e 15 di interfaccia, tutti verdi.

## Screenshot

- Prima: `screenshots/prima/foglio.jpg` (tutte le schermate al commit `568927e`).
- Dopo, primo giro: `screenshots/dopo-1/foglio.jpg` (Oggi, Itinerario, Scalo).
- Dopo, secondo giro: `screenshots/dopo-2/foglio.jpg` (Oggi nei cinque stati, Itinerario,
  Scalo, Nave, Diario, Porti), dopo le cinque note di Matteo.
- Dopo, terzo giro: `screenshots/dopo-3/foglio.jpg` (Diario, Itinerario, Porti), dopo le
  tre note sui timbri: griglia a diametro fisso nel Diario, «Toccato» come badge accanto al
  nome nell'Itinerario.
- Dopo, quarto giro: `screenshots/dopo-4-chiaro/foglio.jpg` e
  `screenshots/dopo-4-scuro/foglio.jpg` — le stesse schermate in **modalità chiara e
  scura**, col cielo luminoso di giorno, le Impostazioni col selettore della livrea.
  Il giro in scuro si fa con `scripts/screenshots.sh --appearance dark`.
- Dopo, quinto giro: `screenshots/dopo-5-chiaro/foglio.jpg` (Diario con la testata
  propria, Oggi in mare) e `screenshots/dopo-5-scuro/foglio.jpg` (Diario, Impostazioni con la
  tinta viva, Nave col pulsante leggibile), dopo le tre note sul quarto giro.
- Le livree: `screenshots/dopo-6-livree/foglio.jpg` — Oggi in porto e in mare con «Rosso»,
  «Blu notte e oro» e «Blu e giallo», in chiaro e in scuro, e il Diario in scuro con l'oro.
  Fatte con `-livrea <id>`; lo script è nel rapporto solo come idea: sei lanci di `simctl`
  con l'argomento in più.
- La barra delle schede: `screenshots/dopo-7-barra/foglio.jpg` — la scheda selezionata con
  `tabTint` su Cruisy, «Rosso», «Blu notte e oro» e «Blu e giallo», in chiaro e in scuro.
- Il cielo alle sei ore: `screenshots/dopo-8-ore/foglio.jpg` — notte con luna e stelle,
  alba, mattina, tramonto, sera, e il tramonto in scuro. Fatte con `-ora <h>`, l'argomento
  DEBUG che finge l'ora di bordo.
- AX5: `screenshots/dopo-9-ax5/foglio.jpg` — Oggi (porto e mare), Itinerario, Scalo, Nave,
  Diario al corpo accessibile più grande, dopo le correzioni ai componenti (timbro in fila
  come badge, «MANCANO» sopra le cifre, righe dell'Itinerario impilate).
- Giro `--lang en`, e AX5 sulle schermate non ancora convertite: **non fatti** (vedi «Da
  fare»).

La cartella `screenshots/` è ignorata da git: si rigenera con `scripts/screenshots.sh`.

---

## Regole del sistema

Questa sezione è il contratto per chi rifà le schermate mancanti. Tutto sta in
`CruisyShared/Design/`.

### 1. Il linguaggio

I documenti di bordo. Ogni scalo è una **carta d'imbarco**; l'itinerario è una **pila di
biglietti**; i porti toccati sono **timbri su un passaporto**. Il fondo è lo **scafo** (blu
livrea), i contenuti stanno sulla **carta** (bianca), il **segnale** (arancio SOLAS) si usa
solo per il rientro a bordo e per i timbri. La cornice — barre, schede, fogli, `Form` — è
iOS 26 e non si ridisegna.

Regola pratica: **personalizzato solo dove c'è il biglietto**, cioè nelle schermate che
mostrano una crociera (Oggi, Itinerario, Scalo, Nave, Diario, Porti, Carta). Impostazioni,
editor, importazione e onboarding restano iOS.

### 2. I token: `Livery` (`CruisyShared/Design/Livery.swift`)

Si legge dall'ambiente: `@Environment(\.livery) private var livery`. La imposta
`RootTabView` con `Livery.resolve(preferences.livery, operatorName: store.shipRecord?.operatorName)`
e la passa anche ai fogli che presenta (l'onboarding); un foglio presentato da altrove eredita
l'ambiente della vista che lo presenta.

| Token | Uso | Contrasto garantito |
|---|---|---|
| `hull` | fondo di ogni schermata della crociera | — |
| `hullDeep` | scrim della carta, fondi delle onde | — |
| `onHull` | testo sullo scafo (bianco) | ≥ 7:1 su `hull` |
| `onHullMuted` | testo di appoggio sullo scafo | ≥ 4,5:1 su `hull` |
| `signalOnHull` | il segnale sullo scafo: scheda selezionata, badge sui giorni di mare | ≥ 4,5:1 su `hull` |
| `paper` | la carta del biglietto: bianca in chiaro, scafo schiarito in scuro | ≥ 1,4:1 da `hull` |
| `paperShade` | il biglietto di dietro nella pila | `ink` ≥ 4,5:1 sopra |
| `ink` | testo sulla carta (di norma = `hull`) | ≥ 7:1 su `paper` |
| `field` | etichette dei campi, testo di appoggio su carta | ≥ 4,5:1 su `paper` |
| `rule`, `perforation` | righe sottili e tratteggio | non testo |
| `signal` | timbri, ora stampata, barre: grafica e testo grande | ≥ 3:1 su `paper` |
| `signalInk` | il segnale come testo piccolo su carta («RIENTRO A BORDO») | ≥ 4,5:1 su `paper` |
| `tint` | controlli di sistema nei `Form` e pulsanti | `ink` in chiaro; in scuro lo scafo reso vivo, ≥ 4,5:1 sul nero |
| `tabTint` | la scheda selezionata nella barra delle schede | `signalInk` in chiaro (≥ 4,5:1 sul vetro chiaro), `signalOnHull` in scuro (≥ 4,5:1 sul vetro scuro) |

**Mai** `signal` per testo piccolo: usare `signalInk`. Mai `onHullMuted` sulla carta né
`field` sullo scafo. Il colore non porta mai significato da solo: accanto c'è sempre una
parola (il timbro ha il testo, il campo ha l'etichetta).

**Le due modalità.** Ogni token è un `Color` dinamico con le varianti chiara e scura
(`Livery.Pair`, `Color(light:dark:)`): in chiaro il biglietto è bianco con l'inchiostro
dello scafo; in scuro il biglietto è di **carta scura** — lo scafo della livrea appena
schiarito — con l'inchiostro chiaro (`darkInkHex`), e lo scafo attorno si fa quasi nero.
Il segnale in scuro è `signalOnHull` schiarito finché regge sulla carta scura. Le varianti
scure si **ricavano** da quelle chiare con il contrasto come vincolo (`lightened`,
`darkened`, `vivid`, `mix`): una livrea nuova va bene in scuro senza scegliere altri
colori, e `LiveryContrastTests` scorre **tutte le livree in entrambe le modalità**.
Quando serve il valore numerico (un `Canvas`, come in `SeaScene`) si legge
`livery.hullPair.hex(scheme)` con lo schema dell'ambiente.

L'app **segue l'aspetto del telefono**: la radice non forza più lo scuro. Le barre sullo
scafo restano scure in entrambe le modalità (`.toolbarColorScheme(.dark)` su barra delle
schede e barre di navigazione delle schermate della crociera), e la barra di stato è
sempre a testo chiaro (`UIViewControllerBasedStatusBarAppearance = NO` in
`Cruisy-Info.plist`). I `Form` di sistema fanno da soli.

`LiveryContrastTests` scorre **tutte** le livree su tutte le coppie: una livrea nuova che
non regge ferma la build. Per aggiungerne una: una voce in `Livery.companies` con la parola
chiave che si confronta col nome dell'armatore ripiegato (`ShipDirectory.fold`), un **nome di
colori** (mai di compagnia — un test lo controlla), e i valori **della sola modalità
chiara**: quelli scuri si ricavano. Le livree ispirate cambiano scafo, testo sullo scafo,
segnale e talvolta `field`/`paperShade`; in chiaro la carta resta bianca.

### 3. La tipografia: `TicketType` (`TicketType.swift`)

Carattere di sistema **con l'asse della larghezza** al posto di Archivo: stesso contrasto
fra stretto e largo, niente file da includere, Dynamic Type gratis.

- `.ticketHour()` — l'ora stampata grande, compressed black, `@ScaledMetric` con tetto.
- `.ticketNumeral()` — un numero grande che non è un'ora (giorni, miglia), condensed black.
- `TicketType.masthead` — il nome della nave sullo scafo, condensed heavy maiuscolo
  (`Masthead`).
- `.ticketEyebrow(color)` — «RIENTRO A BORDO», caption bold spaziata maiuscola.
- `TicketType.place` — «PUERTO PLATA · MOLO 2», subheadline bold condensed maiuscolo.
- `.ticketFieldLabel(color)` / `TicketType.fieldValue` — etichetta e valore di un campo.
- `TicketType.count` — le cifre del countdown, condensed black, **sempre con le ore**
  («0:19:55»: senza, accanto a «17:30» si leggerebbe come un orario).
- `TicketType.stamp` — il testo di un timbro.
- `rowTitle`, `rowDetail`, `body`, `technical`, `chip` — il resto.

Solo `@ScaledMetric` sulle altezze; mai dimensioni fisse per il testo. Ai corpi
accessibili le righe **si impilano**, non si stringono: `AdaptiveHStack` /
`AdaptiveSpacer` (in `CruisyShared/Design/AdaptiveStack.swift`) o `ViewThatFits`; la
colonna della data dell'Itinerario diventa una riga «GIO 10». Il giro AX5 in
`screenshots/dopo-9-ax5` è il riferimento.

### 4. I componenti del biglietto (`Ticket.swift`)

- **`Ticket { top } stub: { stub }`** — carta con perforazione e incavi. La parte alta ha
  l'etichetta, l'ora grande, il luogo e il timbro; la matrice ha il countdown e i campi. Gli
  incavi sono buchi nella forma (`TicketShape`, riempimento pari/dispari), quindi il biglietto
  sta su qualunque fondo.
- **`TicketHead(eyebrow:place:stamp:stampColor:) { hour }`** — l'intestazione: etichetta,
  ora grande, luogo, timbro a destra. Ai corpi accessibili il timbro tondo finiva sopra le
  cifre: lì diventa uno `StampBadge` in fila sotto il luogo. **Usare sempre questa**, non
  ricomporre la testa a mano.
- **`TicketCountRow(label:) { CountdownView(...) }`** — la riga «MANCANO 2:59:52»:
  affiancati, e uno sopra l'altro quando non ci stanno (`ViewThatFits`).
- **`TicketField(label:value:spoken:isSignal:)`** e **`TicketMatrix(fields:columns:)`** — i
  campi, due per riga, uno per riga ai corpi accessibili. `spoken` per VoiceOver quando
  l'abbreviazione non basta.
- **`TicketRule`** — riga sottile fra gruppi di campi.
- **`Stamp("In\nporto", color:rotation:diameter:)`** — timbro a doppio bordo, inclinato.
  Senza `diameter` si allarga finché il testo ci sta intero (mai trattini): è il modo per
  i biglietti, con testi corti e a capo esplicito. Con `diameter` è fisso e il testo si
  adatta: è il modo per le griglie (la pagina dei timbri del Diario, `StampPage`, che
  spezza i nomi sulle parole).
- **`StampBadge("Oggi", color:)`** — il timbro piccolo, rettangolare, per una parola
  accanto a un titolo: «OGGI», «DOMANI», «TOCCATO», «IN CORSO». Non ruba larghezza alla riga.
- **`TicketBehind("Grand Turk · domani 08:00")`** — il biglietto che si intravede dietro.
- **`Masthead(title, detail:)`** — la testata sullo scafo.
- **`.paperCard()`** e **`PaperRow(glyph:title:subtitle:trailing:)`** — carta di servizio per
  ciò che non è un biglietto: righe informative, interruttori, foto. `PaperDisclosure()` in
  coda solo se la riga porta altrove.
- **`HullChip(text, glyph:)`** — pastiglie bordate sullo scafo (meteo).
- **`HullNotice(message, glyph:)`** — l'avviso: un foglietto bianco sullo scafo.
- **`CountdownView(countdown:font:offset:)`** — le cifre che scorrono (in `Cruisy/Views/Components`).
- **`WeatherChips`** — il meteo in pastiglie, con la nota sotto.

### 5. Quando usare cosa

- **Timbro**: per uno **stato**, mai per un'azione. Sul biglietto di oggi: «IN PORTO»,
  «TENDER», «A BORDO», «IN MARE», «A TERRA», «SBARCATI». Sullo scalo: «TOCCATO»,
  «IN PROGRAMMA». Nel Diario: il nome del porto con «×N». Colore `signal` se vivo,
  `field` se passato.
- **Perforazione**: solo dove c'è una matrice sotto un'intestazione con l'ora grande — il
  biglietto di Oggi, quello dello scalo, le carte di bordo della nave, la card delle miglia.
  Una riga di elenco non ha perforazione: è `.paperCard()`.
- **Pila**: `TicketBehind` sopra il biglietto di oggi, per dire cosa viene dopo. Una sola
  costa, mai due.
- **Carta bianca** per tutto ciò che si legge; **scafo** per navigare e respirare.
- **Scena del mare** (`SeaScene(hour:)`): solo in giorno di mare, come fascia fra la testata
  e il biglietto, alta ~250 pt, col biglietto che ci entra di 54 pt. Il cielo parte dallo
  scafo, quindi non ha bordo in cima; di giorno è chiaro e luminoso, all'alba e al tramonto
  caldo, di notte scuro con le stelle (`SeaSceneContrastTests` lo verifica, insieme alla
  continuità); **sopra la scena non va mai testo** — la testata sta sullo scafo, il resto
  sulla carta. Sole e luna seguono l'ora **di bordo** (`store.shipHour`); una nave passa e
  beccheggia. `Riduci movimento` la ferma, fuori dal primo piano si sospende.

### 6. Cosa resta nativo

`TabView` con Liquid Glass (`.tint(livery.tabTint)`: la pastiglia della scheda selezionata è
vetro chiaro in chiaro e scuro in scuro, e il segnale «sullo scafo» sul vetro chiaro
spariva); barre di navigazione (titolo
inline, con lo scafo dietro); `Form` e `List` per Impostazioni, editor, importazione,
riesame; `Toggle`, `Picker`, `DatePicker`, `TextField`, `Menu`, `.searchable`, alert e
`confirmationDialog`; SF Symbols; i pulsanti `.glass` / `.glassProminent` /
`.borderedProminent` (con `livery.tint`, mai `livery.ink`: in scuro l'inchiostro è bianco e
un pulsante bianco con la scritta bianca non si legge). I controlli posati su carta
seguono la modalità come tutto il resto: **non** forzare `.colorScheme` a mano.

La radice (`RootTabView`) **non** impone nessuno schema: l'app segue il telefono. Le barre
sullo scafo sono tenute scure con `.toolbarColorScheme(.dark)`; i `Form` fanno da soli.

### 7. Schermate: fatte e da fare

Fatte nel linguaggio nuovo: Oggi (in porto, in mare, imminente, imbarco domani,
pre-crociera, conclusa), Itinerario, Scalo, Nave, Diario, Porti toccati, Carta (cornice e
matrice di stato), stato vuoto.

**Da convertire, e stato** (ciò che non è segnato «fatto» compila e funziona col design
vecchio):

1. `SettingsSheet` — **fatto**: `Form` nativo con la sezione Livrea (`Picker` su
   `preferences.livery`, riga «Adesso» con la livrea in vigore, piè di pagina che spiega),
   un solo interruttore per la Live Activity con una riga di stato, `.tint(livery.tint)`.
2. `VoyageEditor`, `PortCallEditor` — già `Form`; togliere `Palette` e `Type`
   (`Palette.underway` → `livery.tint`, `Palette.adrift` → `.red`, `Palette.inkPrimary` →
   `.primary`).
3. `ItineraryImportView` — da riscrivere come `Form`: sezione col `TextEditor`, sezione
   coi due pulsanti (scansiona, importa file), piè di pagina con la spiegazione, errore come
   `Label` rossa; overlay di attesa con `ProgressView` su materiale.
4. `ImportReviewView` — `List`/`Form`: sezione riepilogo, «Nave», «Ora di bordo»
   (`ShipClockControls`), una sezione per scalo con i tre `TextField` degli orari; pulsante
   di conferma `.borderedProminent` in `safeAreaInset`.
5. `OnboardingFlow`, `DisclaimerSheet` — fondo di sistema, `.borderedProminent` con
   `livery.tint`; la pagina «Come funziona» come `List`.
6. `LiveActivityRow` / `LiveActivitySetting` — **cancellati** (vedi 1).
7. **Widget e Live Activity** — **fatti nel codice, mai visti a schermo**: su questo Mac
   non si possono aggiungere widget al simulatore. Carta con `livery.paper`, `ink`,
   `signalInk` per «RIENTRO A BORDO», ora grande compressed, countdown con
   `Text(timerInterval:)`; il widget medio ha biglietto e matrice affiancati con una
   perforazione verticale; la schermata di blocco è una matrice di biglietto; la Dynamic
   Island resta bianca e segnale sul nero. La livrea si legge con `LiveryChoice.stored()`
   + `ShipDirectory.shared.lookup(shipName)?.operatorName`; i token sono dinamici, quindi
   chiaro e scuro vengono da soli. I vincoli di `CLAUDE.md` sono rispettati (niente
   `ProgressView` a larghezza infinita nella Dynamic Island, larghezza finita sul
   contatore). **Da provare sul telefono per primi.**
8. Poi **cancellare** `Palette.swift`, `Typography.swift`, `GlassSurface.swift`,
   `AdaptiveStack.swift` (se non più usato), `InfoRow.swift`, `MetricRow.swift`,
   `ProvenanceChip.swift`, `VoyageStore+Legacy.swift`, e `PaletteContrastTests` (sostituito
   da `LiveryContrastTests`). Il grep da fare a vuoto: `grep -rn "Palette\.\|Type\.\|glassSurface\|glassCapsule" Cruisy CruisyWidgets`.

Poi: `scripts/sync-strings.sh` con le traduzioni inglesi, e i giri `--lang en` e
`--size AX5` su tutte le schermate. I timbri in inglese: «IN PORT», «AT SEA», «ASHORE»,
«ABOARD», «TENDER», «LANDED», «VISITED», «PLANNED».

---

## Cosa è cambiato, e perché

### Backend

**Swift 6 e attori.** Tutti i target sono in modalità Swift 6 con
`SWIFT_APPROACHABLE_CONCURRENCY` (= `NonisolatedNonsendingByDefault` +
`InferIsolatedConformances`). I servizi `@Observable` con metodi `async` sono `@MainActor`:
`LiveActivityController`, `NotificationScheduler`, `LocationService`, `PositionService`,
`Reachability`, `ItineraryImporter`, oltre a quelli che già lo erano. I delegati di
CoreLocation e VisionKit usano conformanze `@preconcurrency` (chiamano sul thread
principale). `SeaChart: @preconcurrency Animatable`. `VoyageStore` ha `isolated deinit` per
il timer. In `LiveActivityController.update` l'attività si rilegge da
`Activity.activities` invece che da una proprietà dell'attore, se no ActivityKit rifiuta il
valore. Nessun avviso di concorrenza residuo.

**`VoyageStore` diviso.** `Preferences` (unità, avviso letto, Live Activity, rotta,
livrea — in `UserDefaults`, con `ephemeral` per test e anteprime), `LogbookStore` (il diario
e il suo file), `TrackRecorder` (la rotta e il suo file, `writesToDisk` per demo e test),
`VoyageStore` (crociera, `now`, ticker, e la coordinazione: `recordProgress` a ogni battito,
`closeOut` alla sostituzione). Le viste leggono `Preferences`, `LogbookStore` e
`TrackRecorder` dall'ambiente (`CruisyApp` li inietta). Comportamento invariato: i test
esistenti passano con solo il rinominare di due chiamate.

**Rete.** `NetworkClient` (session, user agent, timeout, `Cost.frugal` per le foto che
imposta `allowsExpensiveNetworkAccess` secondo `PhotoDownloadPolicy`, `json`/`decode`/`image`
con errori dichiarati `.status`/`.malformed`). `Commons`, `ShipLookupService` e
`MarineWeatherService` ci passano. Nessuna chiamata nuova verso nessuno: `docs/index.html`
resta valido.

**Foto.** `Commons.readCache`/`writeCache` sono `@concurrent`: decodifica e ricompressione
JPEG fuori dal thread principale.

**Batteria.** `LocationProfile`: in tasca `kCLLocationAccuracyHundredMeters`, filtro 300 m,
`activityType = .otherNavigation`; in primo piano dieci metri e 50 m come prima. I numeri
sono misurati contro `Track.minimumSeparation` (0,25 mn = 463 m) e testati. La misura vera
la fa Matteo con il telefono in tasca.

**Persistenza.** `PersistenceCompatibilityTests`: crociera del primo formato (orologio a
scarto unico, scali senza fuso, senza `updatedAt`), riconciliazione, chiavi vecchie
dell'orologio scritte ancora oggi, diario con e senza rotta, file della traccia, navi
imparate. **Difetto trovato e corretto**: `LoggedVoyage` non nominava `track` fra le
`CodingKeys`, quindi la rotta registrata non veniva né scritta né riletta dal diario.

### Design, schermata per schermata

- **Oggi.** Testata sullo scafo (`Masthead`), il prossimo scalo dietro (`TicketBehind`), il
  biglietto (`BoardingPass`): in porto l'ora del rientro a bordo, in mare l'ora d'arrivo,
  prima dell'imbarco l'ora d'imbarco o i giorni. La matrice ha il countdown (sempre con le
  ore) e i campi. **La striscia «il telefono è 6 ore avanti» non c'è più**: è il campo «Il
  telefono» nella matrice, in colore segnale, solo quando non concorda. In giorno di mare la
  `SeaScene` sta fra testata e biglietto. Sotto: avvisi (`HullNotice`), meteo in pastiglie,
  foto della nave (solo pre-crociera, e **una sola volta**: senza foto c'è la rotta, non
  ripetuta), cartolina della carta, distanza dalla nave, prossimo scalo, Meteo di Apple.
- **Itinerario.** Matrici di biglietto per i giorni in porto (oggi più alta, «Oggi» /
  «Domani» come badge inclinato, «TOCCATO» come timbro per il passato — non più carta
  grigia), giorni di mare come righe sullo scafo con le onde.
- **Scalo.** `PortTicket` (timbro «IN PORTO», «TENDER», «TOCCATO», «IN PROGRAMMA»), carta in
  cornice di carta, meteo all'arrivo, riga dell'ormeggio, card degli avvisi con `Toggle` e
  `Picker` nativi su carta, correzione degli orari.
- **Nave.** Foto (o rotta) su carta, testata, «Carte di bordo» come biglietto con la
  matrice (stazza, misure, anno, bandiera, IMO, MMSI), riga della livrea in vigore, scheda
  per la nave mancante con pulsante nativo.
- **Diario.** Card delle miglia come biglietto (numero grande, totali, barra del traguardo,
  paragoni); pagina dei timbri (`StampPage`: cerchi inclinati a inclinazioni fisse, anno
  sotto); primati; crociere come matrici. **Segue lo sfondo come le altre schede** (difetto
  chiuso: il fondo è lo scafo ovunque).
- **Porti toccati.** Card di carta con foto e timbro delle visite.
- **Carta.** Scrim con `hullDeep`, testata condensed, matrice di stato su carta con la
  provenienza della posizione come campo.
- **Stato vuoto.** Biglietto tratteggiato e pulsanti.

### Difetti noti: stato

- Rotta due volte in pre-crociera: **chiuso** (foto o rotta, mai entrambe).
- Striscia del fuso in cima a Oggi: **chiuso** (campo nella matrice).
- Diario e Porti con lo sfondo diverso: **chiuso**.
- Doppio interruttore della Live Activity nelle Impostazioni: **chiuso** (la preferenza,
  più una riga di stato).
- Traguardo «Lo Stretto di Gibilterra fino alle Baleari»: **chiuso** («Da Gibilterra a
  Palma», dettaglio «lo Stretto → le Baleari»).
- Carta senza ingrandimento dalla card: **aperto**, resta il push (motivo in
  `TodayScreen`).
- Foto dei porti di qualità imprevedibile: **aperto**.
- «Sun Princess» mancante in `ships.bin`: **aperto** (serve rigenerare il database).
- Figma indietro: **non toccato** (serve il server autorizzato).

---

## Stato dei test

- Unitari: **243** in 34 suite, tutti verdi (`scripts/test.sh unit`). Nuove suite:
  `PersistenceCompatibilityTests` (7), `LocationProfileTests` (4), `NetworkClientTests` (5),
  `LiveryContrastTests` (9, parametrizzati su tutte le livree × le due modalità, compresa
  la scheda selezionata sul vetro chiaro e scuro),
  `SeaSceneContrastTests` (4: giorno chiaro, alba e tramonto caldi, continuità, sole e luna).
- Interfaccia: **15**, tutti verdi (`scripts/test.sh ui`). Non aggiunti quelli per
  importazione, editor e impostazioni: da fare sul modello di `NavigationSmokeUITests`
  (`-open importazione` + scrivere nel `TextEditor` + «Leggi» → «Controlla»; `-open editor`
  + cambiare il nome + «Salva»; `-open impostazioni` + `Picker` della livrea).

## Da fare (in ordine)

1. Editor, importazione, riesame, onboarding nativi (7.2–7.5).
2. Provare widget e Live Activity sul telefono (7.7): sono scritti, non visti.
3. Cancellare il design vecchio (7.8) e `PaletteContrastTests`.
4. `scripts/sync-strings.sh`, traduzioni inglesi, `LocalizationTests` verde.
5. Screenshot `--lang it`, `--lang en`, `--size AX5` e `--appearance dark` su tutte le
   schermate, senza testo tagliato. Attenzione ai timbri e all'ora grande ad AX5: hanno
   tetti e `minimumScaleFactor`, ma vanno guardati.
6. Test di interfaccia per importazione, editor e impostazioni.

**Cosa resta da convertire in scuro.** Le schermate rifatte usano solo token dinamici e
sono già a posto in entrambe le modalità (verificate nel quarto giro: Oggi, Itinerario,
Scalo, Nave, Diario). I `Form` (Impostazioni, editor, importazione, onboarding) sono di
sistema e seguono la modalità da soli. Widget e Live Activity usano i token dinamici,
ma vanno **visti sul telefono** in entrambe le modalità. Da guardare a mano, in scuro,
anche la Carta (scrim e matrice di stato) e la pagina dei Porti toccati, che nei giri
in scuro non c'erano.

## Domande per Matteo

- Nessuna delle cose in «Da chiedere prima» è stata toccata: niente rotta registrata sulla
  carta, niente notifiche «time sensitive», niente cambi alla privacy o al meteo.
- **Archivo**: ho usato il carattere di sistema con l'asse della larghezza (compressed per
  l'ora, condensed per testate e countdown). È l'opzione «se cambi carattere, tieni un
  grottesco con più larghezze» del passaggio di consegne, e non richiede di scaricare né
  includere niente. Se vuoi Archivo davvero: i file OFL in `Cruisy/Resources/Fonts/`,
  `UIAppFonts` in `Cruisy-Info.plist`, e i quattro `Font.system(...).width(...)` di
  `TicketType` diventano `Font.custom("Archivo", size:, relativeTo:)` con le varianti di
  larghezza. Il resto del sistema non cambia.
- Le livree ispirate: 17 palette, nomi di colori. Vuoi vederle tutte prima di decidere
  quali tenere? `Livery.all` le elenca; un'anteprima in Impostazioni sarebbe il posto.

## Da provare sul telefono

- **Widget della schermata Home, Live Activity e Dynamic Island**, rifatti nel linguaggio
  del biglietto senza poterli vedere: `-sample deviceTest` per il widget, `-liveActivity`
  per l'attività. Guardarli in chiaro e in scuro, e con una livrea di compagnia.
- La rotta registrata col telefono in tasca **col profilo nuovo** (`LocationProfile.recording`):
  consumo in una giornata di mare e qualità della traccia nel diario.
- Il collegamento a Meteo di Apple (`weather://`).
- La scena del giorno di mare: fluidità delle onde e della nave, e che si fermi con Riduci
  movimento e in secondo piano.
- I gesti sulla carta.
