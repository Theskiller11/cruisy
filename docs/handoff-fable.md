# Passaggio di consegne a Fable 5.1

Scritto il 14 settembre 2026, alla fine di tre settimane di lavoro con Matteo. Prima di questo file leggi
`CLAUDE.md`: lì ci sono i principi che non si toccano, i comandi e le trappole già pagate.

## La missione

Matteo ti affida l'app per **una revisione completa e un redesign**. Ha detto, testualmente, che il
design fatto finora **non gli piace**, e ti dà il permesso di **smontarlo del tutto**: colori, caratteri,
componenti, layout, e anche la struttura della navigazione se lo giustifichi. Non devi conservare niente
dell'aspetto di oggi.

Sono tre lavori, in quest'ordine di importanza:

1. **Il redesign** nella direzione che Matteo ha scelto, descritta qui sotto.
2. **La revisione del "backend"**: servizi, concorrenza, persistenza, rete, batteria, test.
3. **La chiusura dei difetti noti**, molti dei quali spariranno col redesign.

Lavora a lungo e in autonomia. Dopo ogni blocco di lavoro: test verdi e screenshot. Non fermarti a chiedere
per scelte di mestiere; fermati solo per quelle nella sezione «Da chiedere prima».

---

## 1. La direzione di design: Biglietto d'imbarco, con i piedi in iOS

Il riferimento visivo è `docs/design/quattro-facce-per-cruisy.html`, **direzione D**. Per vederlo senza
browser: `scripts/render-html.swift`. Matteo l'ha scelta con tre modifiche, e le modifiche contano quanto
il mock.

### Il cuore: i documenti di bordo come linguaggio

- **Ogni scalo è una carta d'imbarco.** In porto la cosa più grande è **l'ora del rientro a bordo**,
  stampata come su un biglietto (17:30), e il countdown ne è la conseguenza. Si ricorda un'ora, non dei
  secondi.
- Il biglietto ha una **matrice** con i campi — attracco, partenza, molo o tender, sosta — separata da
  una **perforazione**. Il prossimo scalo si intravede **dietro**, come una pila di biglietti.
- **Timbri** per gli stati: «in porto», «a bordo», «tender». Nel Diario i porti toccati possono diventare
  timbri su un passaporto: è il posto naturale per quel vocabolario.
- Carattere di riferimento: **Archivo** (OFL, asse della larghezza), stretto e nero per le ore, normale
  per il resto. Se cambi carattere, tieni un grottesco con più larghezze: il biglietto vive di contrasto
  fra stretto e largo.
- Colori di riferimento: livrea blu `#0E2A47`, carta `#FFFFFF`, **arancio SOLAS** `#E4570F` (quello di
  salvagente e scialuppe) usato solo per il rientro a bordo e i timbri.

### Modifica 1 — elementi nativi di iOS

Matteo lo ha detto con un esempio: **la barra delle schede**. Il biglietto è il contenuto; la cornice resta
iOS 26.

- `TabView` nativa con Liquid Glass, non una barra disegnata.
- Barre di navigazione, fogli, menu, `Form` di Impostazioni, editor e importazione **nativi**, al massimo
  colorati con la tinta della livrea.
- SF Symbols per le icone di sistema.
- Gesti, transizioni e swipe indietro di sistema (vedi le trappole in `CLAUDE.md`).

La regola pratica: **personalizzato solo dove c'è il biglietto**, cioè nelle schermate che mostrano una
crociera. Tutto quello che è impostazione o inserimento dati resta com'è in iOS.

### Modifica 2 — il giorno di mare si anima

Il biglietto calza in porto; in navigazione Matteo vuole **un'illustrazione viva**:

- **onde che si muovono**;
- **il sole che sorge e tramonta** secondo l'ora di bordo (`store.shipHour`, già calcolata), la luna e il
  cielo scuro di notte;
- sopra, il biglietto verso il prossimo scalo, con l'arrivo come ora stampata.

È l'eredità della direzione A della pagina dei mock. Vincoli: **Riduci movimento** ferma l'animazione e
lascia la scena immobile; l'animazione si sospende quando l'app non è in primo piano; il testo sopra la
scena deve restare a contrasto AA a **ogni** ora. Il modo più sicuro è che il testo stia sulla carta
bianca del biglietto, non sul cielo.

### Modifica 3 — la livrea cambia con la compagnia

I colori dell'app seguono la compagnia della crociera. Gli esempi di Matteo: MSC bianco e blu, Explora
navy e oro, Virgin Voyages rosso. La compagnia si ricava dalla nave (`ShipRecord.operatorName`,
da Wikidata), quindi funziona senza rete.

**Vincolo legale, non estetico** (App Store 5.2.1, proprietà intellettuale):

- sì a **palette ispirate** ai colori di una compagnia;
- **no a loghi, caratteri proprietari, motivi grafici riconoscibili** e al nome della compagnia usato come
  marchio. Il nome può comparire solo come dato, dove c'è già: la scheda della nave;
- nessuna apparenza di affiliazione. Negli screenshot per l'App Store **solo la livrea di Cruisy**;
- una **livrea di Cruisy** di serie, per le navi sconosciute e per chi preferisce;
- una scelta in Impostazioni: livrea della compagnia oppure livrea Cruisy.

Ogni livrea passa i test di contrasto: estendi `PaletteContrastTests` perché li scorra **tutte**.

### Da consegnare per il design

- Un sistema di token nuovo al posto di `Palette`, `Type` e `GlassSurface`, con i test di contrasto.
- I componenti del biglietto: matrice, perforazione, campi, timbro, pila.
- **Tutte** le schermate rifatte: Oggi (in porto, in mare, imbarco imminente, pre-crociera), Carta,
  Itinerario, dettaglio dello scalo, Nave, Diario, tutti i porti, Impostazioni, editor, importazione,
  onboarding.
- **Widget e Live Activity** nello stesso linguaggio, dentro i loro vincoli (vedi `CLAUDE.md`).
- Caratteri inclusi nell'app con la licenza in `Cruisy/Resources/Fonts/`, registrati con `UIAppFonts` in
  `Cruisy-Info.plist` — **non** con `INFOPLIST_KEY`, che per quella chiave non funziona — e usati con
  `Font.custom(_:size:relativeTo:)` perché seguano Dynamic Type.

---

## 2. Revisione del "backend"

Cruisy non ha un server: qui "backend" vuol dire i servizi, i dati e tutto quello che sta sotto le viste.

1. **Concorrenza.** Il progetto è in Swift 5 senza controlli. Metti `SWIFT_STRICT_CONCURRENCY = complete`
   (o passa a Swift 6) e correggi quello che esce. Già sospetti, perché sono `@Observable` con metodi
   `async` e non sono legati a nessun attore: `LiveActivityController`, `NotificationScheduler`,
   `ItineraryImporter`, `LocationService`, `PositionService`. Il crash della schermata dei porti del
   14 settembre veniva esattamente da qui.
2. **`VoyageStore` fa troppe cose**: crociera, diario, traccia, preferenze, orologio, archivio. Dividilo in
   pezzi con una responsabilità ciascuno, senza cambiare il comportamento. I test esistenti sono la rete di
   sicurezza.
3. **Cache delle foto**: legge e scrive JPEG sul thread principale (`Commons.readCache`, `writeCache`).
   Spostala fuori.
4. **Rete**: tre client scritti a mano (`Commons`, `ShipLookupService`, `MarineWeatherService`). Valuta un
   livello comune per timeout, user agent, cache e rispetto delle reti a consumo (`PhotoDownloadPolicy`).
5. **Batteria della rotta registrata**: oggi `kCLLocationAccuracyNearestTenMeters` con filtro a 50 m anche
   durante la registrazione. In mare aperto basta molto meno. Misura e documenta la scelta.
6. **Persistenza**: le crociere salvate prima di ogni cambio di formato devono continuare a leggersi. Ci sono
   test per `ShipClock` e i fusi; controlla che ci siano per ogni formato su disco (crociera, diario,
   traccia).
7. **Test**: aggiungi test di interfaccia per importazione, editor e impostazioni, sul modello di
   `NavigationSmokeUITests`.

## 3. Difetti noti

Il rapporto completo, con le schermate, è in `docs/design/a-che-punto-e-cruisy-2026-09-14.html`. Quelli
ancora aperti, che il redesign deve risolvere o almeno non riprodurre:

- In pre-crociera, se la nave non ha foto, la **rotta compare due volte**: testata e card.
- La **striscia «il telefono è 6 ore avanti»** sta sempre in cima a Oggi per chi tiene l'ora di casa.
  Occupa il posto migliore; va ripensata.
- Il **Diario e la schermata dei porti** non seguono lo sfondo dell'ora come le altre schede.
- Nelle **Impostazioni** l'interruttore della Live Activity compare **due volte**: la preferenza e la
  riga di controllo.
- Il traguardo «**Lo Stretto di Gibilterra fino alle Baleari**» ha un nome goffo e sbagliato: è la rotta
  Gibilterra–Palma.
- La carta non si **ingrandisce più dalla card**: la transizione a zoom è stata tolta perché chiudeva la
  carta col pinch. Un'alternativa senza quel gesto sarebbe benvenuta.
- Le **foto dei porti** vengono dall'immagine di apertura di Wikipedia: qualità imprevedibile.
- **Nomi mancanti** nel database delle navi, per esempio *Sun Princess*.
- **Figma** è indietro rispetto al codice: stili di testo rotti, variabili con la palette vecchia. È
  facoltativo, e serve il server Figma autorizzato.

## 4. Da chiedere prima a Matteo

- Mostrare la **rotta registrata sulla carta**: oggi va solo nel Diario, per sua scelta.
- Rendere le **notifiche «time sensitive»**: il suo profilo di sviluppatore non ha quella capability.
- **Licenza del meteo** e modello di pubblicazione: Open-Meteo è gratuito solo per uso non commerciale.
- Qualunque cosa che **esca dal telefono** o cambi l'informativa privacy.
- `git push`, pubblicazione, modifiche al MeteoProxy sul TrueNAS: **mai**, senza richiesta esplicita.

## 5. Si verifica solo su un iPhone vero

Da lasciare a Matteo, con istruzioni chiare nel rapporto finale:

- Dynamic Island espansa e Live Activity; widget della schermata Home.
- La rotta registrata col telefono in tasca, e il consumo di batteria in una giornata.
- Il collegamento a Meteo di Apple (`weather://` non è documentato; sul simulatore Meteo non c'è).
- La sensazione dei gesti sulla carta e delle animazioni del giorno di mare.

## 6. Come lavorare

1. **Parti misurando.** `scripts/test.sh all` (oggi: 214 unitari e 15 di interfaccia, tutti verdi) e
   `scripts/screenshots.sh --out screenshots/prima`. Guarda il foglio: è il punto di partenza.
2. **Dopo ogni blocco** — un componente, una schermata, un servizio — test e screenshot delle schermate
   toccate. Guarda gli screenshot davvero: su questo Mac sono l'unico modo di vedere l'app.
3. **Prima di finire**: `scripts/sync-strings.sh`, traduzione in inglese, e i giri di screenshot in
   `--lang it`, `--lang en` e `--size AX5` su tutte le schermate, senza testo tagliato. Tutti i test verdi.
4. **I test di interfaccia cercano gli elementi per etichetta.** Se cambi un testo, aggiorna il test, non
   toglierlo: quei test hanno già trovato due crash e un gesto rotto.
5. **Rapporto finale** in `docs/fable-report.md`: cosa hai cambiato e perché, dove sono gli screenshot prima
   e dopo, cosa resta aperto, cosa Matteo deve provare sul telefono.
6. **Commit.** Matteo vuole che i commit li faccia tu **alla fine del lavoro**. Lavori in un worktree
   separato, quindi il ramo principale non si tocca: se il lavoro è lungo, un commit intermedio sul tuo ramo
   quando un blocco è finito e verde è una rete di sicurezza, non un'infrazione. Messaggi in italiano, con la
   riga `Co-Authored-By` del modello che scrive.

## Copia remota del progetto

Il progetto oggi esiste solo su questo Mac, e il comando `gh` non è installato. Quando Matteo crea un
repository privato vuoto, bastano due comandi dalla cartella del progetto:

```bash
git remote add origin <indirizzo-del-repository>
git push -u origin master
```

Non lanciarli tu: pubblicano il codice, e li decide Matteo.
