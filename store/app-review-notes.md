# Note per la revisione Apple

Da incollare in App Store Connect, **App Review Information › Notes**, a ogni invio che contiene la
registrazione della rotta. La posizione in background è una delle voci che più spesso fermano la
revisione (linee guida 2.5.4 e 5.1.1): i revisori vogliono sapere **a cosa serve, come si accende e come
lo verificano**, e se non lo trovano scritto respingono e chiedono.

Consigli prima di inviare:

- **Registra un video breve** (30–60 secondi) che mostra Impostazioni › Rotta › interruttore, il dialogo
  del permesso, l'indicatore blu della posizione, e il Diario con la traversata. Caricalo nello stesso
  campo come allegato, o mettilo in un link non indicizzato.
- Verifica che il testo del permesso («Serve solo se accendi la registrazione della rotta…») sia quello
  dell'app compilata: `/usr/libexec/PlistBuddy -c "Print :NSLocationAlwaysAndWhenInUseUsageDescription"`
  sul `.app`. Il test `InfoPlistTests` lo controlla, ma il revisore legge quello che vede.
- L'informativa privacy pubblicata deve dire la stessa cosa: https://cruisy.matteopapini.com/privacy (sorgente `docs/site/privacy.html`), sezione «La posizione».

---

## Testo da incollare (inglese)

Cruisy is a countdown app for cruise passengers: it tells you how long until "all aboard" when the ship
is in port, and how long until arrival at the next port when it is at sea.

**Background location ("Always") is optional and off by default.** It is used for one feature only:
recording the route the ship actually sails. Passengers use it to see the crossing drawn in the app's
logbook and to count the real nautical miles travelled, instead of straight lines between ports.

Why it must run in the background: the phone stays in a pocket or cabin for most of a sea day, and in
the open ocean there is no cellular signal, so significant-location-change monitoring never fires.
Standard location updates with the location background mode are the only way to record a ship's track
at sea.

How it is limited:
- It starts only when the user turns on Settings › Route › "Record the route sailed". The Always
  permission is requested at that moment, not at launch.
- It stops automatically when the cruise ends (after the final port), and whenever the user turns the
  switch off or withdraws the permission.
- The blue location indicator is shown while recording (`showsBackgroundLocationIndicator`).
- Points are recorded at most every 2 minutes and only after 0.25 NM of movement, to limit battery use.
- Location data never leaves the device. The app has no server and no analytics.

Without the permission, everything else in the app works: countdowns come from the published itinerary,
and the map uses the phone's position only while the app is open ("When In Use").

How to test (no account needed):
1. Launch the app and complete onboarding.
2. Create or import a cruise, or open any sample file.
3. Go to Itinerary › gear icon › Settings › Route and turn on "Record the route sailed".
4. Allow location "While Using", then "Change to Always Allow" when iOS asks.
5. Move with the device (for example in a car) for a few minutes. Settings › Route shows the number of
   recorded points and the real miles; the logbook shows them when the cruise ends.

Photos of ships and ports are downloaded from Wikimedia Commons and Wikipedia with their author credit,
and not on metered networks unless the user allows it. Weather comes from Open-Meteo.

---

## Da ricordare per le risposte

- **Se chiedono perché non basta «Quando in uso»**: in mare il telefono resta in tasca o in cabina per
  ore, e l'app sospesa non riceve posizioni. La traccia avrebbe buchi di intere giornate.
- **Se chiedono perché non i cambiamenti significativi**: si appoggiano alle celle telefoniche, che in
  mare aperto non ci sono.
- **Se chiedono della batteria**: filtro a 0,25 miglia e 2 minuti in `Track.append`, spegnimento
  automatico allo sbarco in `RootTabView` (`trackingKey`), nessuna pausa automatica perché iOS
  scambierebbe una nave a velocità costante per una nave ferma.
