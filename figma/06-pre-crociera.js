// --- Pre-crociera, l'attesa ------------------------------------------------
// Si accende oltre le 12 ore dall'imbarco. A crociera lontana non c'è niente da
// misurare al secondo, quindi non si mostrano strumenti: quanti giorni mancano,
// una frase, e due righe di contorno.
//
// NB: questo script **non usa il preambolo**: si porta i propri aiutanti, perché
// serve anche il peso Bold per il nome della nave e una `infoRow` che gli altri
// non hanno.

const W = 402, H = 874;
const page = await figma.getNodeByIdAsync("6:5");
await figma.setCurrentPageAsync(page);

for (const f of [
  { family: "SF Pro", style: "Regular" },
  { family: "SF Pro", style: "Medium" },
  { family: "SF Pro", style: "Semibold" },
  { family: "SF Pro", style: "Bold" },
  { family: "SF Pro Rounded", style: "Semibold" },
  { family: "Roboto Mono", style: "Medium" }
]) await figma.loadFontAsync(f);

const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));
const TS = Object.fromEntries((await figma.getLocalTextStylesAsync()).map(s => [s.name, s]));
const ES = Object.fromEntries((await figma.getLocalEffectStylesAsync()).map(s => [s.name, s]));

const paint = (n) => figma.variables.setBoundVariableForPaint(
  { type: "SOLID", color: { r: 0, g: 0, b: 0 } }, "color", V[n]);
const rgba = (n, a) => {
  const v = V[n], c = v.valuesByMode[Object.keys(v.valuesByMode)[0]];
  return { r: c.r, g: c.g, b: c.b, a: a === undefined ? (c.a === undefined ? 1 : c.a) : a };
};
const wash = (n, a) => ({ type: "SOLID", color: rgba(n), opacity: a });

// Gli stili di testo del file possono portare impostazioni di font variabile che
// l'SF Pro installato non accetta più — `wdth` non è più un asse valido, e lo è
// diventato fra il 1° e il 7 settembre 2026. Un solo stile rotto faceva fallire
// **tutta** la schermata: qui invece si ripiega su un font sicuro copiando le
// misure dello stile, così la gerarchia tipografica regge, e i nomi degli stili
// che hanno ceduto tornano nel valore di ritorno invece di restare un mistero.
const SICURO = { family: "SF Pro", style: "Regular" };
const stiliRotti = [];
const txt = (stile, contenuto, coloreVar, opts) => {
  opts = opts || {};
  const st = TS[stile];
  const t = figma.createText();
  let conStile = false;
  if (st) {
    try { t.fontName = st.fontName; conStile = true; }
    catch (e) {
      if (stiliRotti.indexOf(stile) < 0) stiliRotti.push(stile);
      t.fontName = SICURO;
    }
  } else {
    if (stiliRotti.indexOf(stile) < 0) stiliRotti.push(stile + " (inesistente)");
    t.fontName = SICURO;
  }
  t.characters = contenuto;
  if (conStile) {
    try { t.textStyleId = st.id; } catch (e) { conStile = false; }
  }
  if (!conStile && st) {
    if (st.fontSize) t.fontSize = st.fontSize;
    if (st.lineHeight) { try { t.lineHeight = st.lineHeight; } catch (e) {} }
    if (st.letterSpacing) { try { t.letterSpacing = st.letterSpacing; } catch (e) {} }
  }
  if (coloreVar) t.fills = [paint(coloreVar)];
  if (opts.upper) t.textCase = "UPPER";
  t.name = opts.name || contenuto.slice(0, 24);
  return t;
};
const col = (s, o) => { const f = figma.createAutoLayout("VERTICAL", Object.assign({ itemSpacing: s }, o || {})); f.fills = []; return f; };
const row = (s, o) => { const f = figma.createAutoLayout("HORIZONTAL", Object.assign({ itemSpacing: s }, o || {})); f.fills = []; return f; };
const pad = (f, o, v) => { f.paddingLeft = f.paddingRight = o; f.paddingTop = f.paddingBottom = (v === undefined ? o : v); return f; };

const glifiMancanti = [];
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  try { t.characters = figma.util.getSfSymbolCharacter(nome); }
  catch (e) { if (glifiMancanti.indexOf(nome) < 0) glifiMancanti.push(nome); t.characters = "●"; }
  t.name = "icona/" + nome;
  if (coloreVar) t.fills = [paint(coloreVar)];
  return t;
};

const barraSchede = (attiva) => {
  // Quattro voci, non cinque: la Carta non è più una scheda — si apre dalla card
  // e si chiude col tasto indietro, perché una scheda per una destinazione che si
  // raggiunge già da un tocco era ridondante.
  const schede = [["Oggi","sun.horizon"],["Itinerario","list.bullet.indent"],
    ["Nave","ferry"],["Diario","book.closed"]];
  const barra = row(0, { name: "Barra delle schede" });
  barra.primaryAxisAlignItems = "SPACE_BETWEEN";
  barra.counterAxisAlignItems = "CENTER";
  pad(barra, 8, 8);
  barra.cornerRadius = 34;
  barra.fills = [wash("fondo/vetro", 0.92)];
  barra.strokes = [paint("bordo/sottile")];
  barra.strokeWeight = 0.5;
  if (ES["Vetro / Chrome"]) barra.effectStyleId = ES["Vetro / Chrome"].id;
  for (const [nome, simbolo] of schede) {
    const scelta = nome === attiva;
    const c = col(3, { name: nome });
    c.counterAxisAlignItems = "CENTER";
    pad(c, 14, 8);
    if (scelta) { c.cornerRadius = 26; c.fills = [wash("accento/navigazione", 0.14)]; }
    c.appendChild(glifo(simbolo, 20, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    c.appendChild(txt("Etichetta metrica", nome, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    barra.appendChild(c);
  }
  return barra;
};

/** Glifo in un quadratino tinto, titolo e sottotitolo.
 *  La freccia non c'è: compare solo se la riga porta davvero da qualche parte. */
const infoRow = (simbolo, tinta, titolo, sottotitolo) => {
  const r = row(12, { name: titolo });
  r.counterAxisAlignItems = "CENTER";
  pad(r, 15, 13);
  r.cornerRadius = 20;
  r.fills = [paint("fondo/vetro")];
  r.strokes = [paint("bordo/sottile")];
  r.strokeWeight = 0.5;
  if (ES["Vetro / Chip"]) r.effectStyleId = ES["Vetro / Chip"].id;
  const box = row(0, { name: "glifo" });
  box.primaryAxisAlignItems = "CENTER";
  box.counterAxisAlignItems = "CENTER";
  box.resize(34, 34);
  box.layoutSizingHorizontal = "FIXED";
  box.layoutSizingVertical = "FIXED";
  box.cornerRadius = 11;
  box.fills = [wash(tinta, 0.16)];
  box.appendChild(glifo(simbolo, 15, tinta));
  r.appendChild(box);
  const c = col(2);
  c.appendChild(txt("Titolo riga", titolo, "inchiostro/primario"));
  c.appendChild(txt("Dettaglio riga", sottotitolo, "inchiostro/secondario"));
  r.appendChild(c);
  c.layoutSizingHorizontal = "FILL";
  return r;
};

/** Un colore esadecimale come lo scrive `Palette`.
 *
 *  L'alfa **ci vuole**: le fermate di un gradiente lo pretendono, e senza si prende
 *  «Required value missing at gradientStops[0].color.a». I riempimenti pieni invece
 *  lo ignorano, quindi metterlo sempre è la scelta che non fa danni. */
const hex = (h) => ({ r: ((h >> 16) & 255) / 255, g: ((h >> 8) & 255) / 255, b: (h & 255) / 255, a: 1 });

const s = figma.createFrame();
s.name = "Pre-crociera — attesa";
s.resize(W, H);
s.x = 2300; s.y = 0;
s.clipsContent = true;
// Il cielo di **giorno** in mare. Non sono le variabili del sistema perche' quelle
// tengono un solo fondo, mentre in codice il gradiente ora si muove con l'ora di
// bordo: tre fermate, tutte e tre. Questi sono i valori di mezzogiorno, cioe' i
// colori che Matteo ha disegnato scalati finche' l'inchiostro terziario sopra una
// card di vetro tiene 4,5:1.
s.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: hex(0x072035) },
    { position: 0.5, color: hex(0x051522) },
    { position: 1, color: hex(0x05131F) }
  ]
}];
page.appendChild(s);

// La testata è **la fotografia della nave**, che sfuma nel fondo. Prima qui c'era
// la carta della rotta: la rotta è scesa nella card più sotto, dove è toccabile,
// e la foto ha preso il suo posto — è quella che fa venire voglia di partire.
//
// In codice l'immagine sta in un `overlay`, non come figlia diretta: un'immagine
// `.fill` come figlia imporrebbe la propria larghezza alla colonna, e "Icon of the
// Seas" diventerebbe "on of the Seas". Qui è un riquadro da sostituire a mano con
// `upload_assets`, perché la foto viene da Wikimedia Commons e non da un vettore.
const eroe = figma.createFrame();
eroe.name = "Testata — foto della nave";
eroe.resize(W, 300);
eroe.x = 0; eroe.y = 0;
eroe.clipsContent = true;
eroe.fills = [wash("fondo/mare-alto", 1)];
s.appendChild(eroe);

const foto = figma.createFrame();
foto.name = "Foto della nave — sostituire con l'immagine di Commons";
foto.resize(W, 300);
foto.x = 0; foto.y = 0;
foto.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[1, 0, 0], [0, 1, 0]],
  gradientStops: [
    { position: 0, color: hex(0x123249) },
    { position: 1, color: hex(0x0A2130) }
  ]
}];
eroe.appendChild(foto);

const velo = figma.createRectangle();
velo.name = "Velo";
velo.resize(W, 300);
velo.x = 0; velo.y = 0;
velo.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: { r: 0, g: 0, b: 0, a: 0 } },
    { position: 0.55, color: rgba("fondo/abisso", 0.55) },
    { position: 1, color: rgba("fondo/abisso", 1) }
  ]
}];
eroe.appendChild(velo);

const nomi = col(4, { name: "Nome e rotta" });
const nomeNave = figma.createText();
nomeNave.fontName = { family: "SF Pro", style: "Bold" };
nomeNave.fontSize = 34;
nomeNave.lineHeight = { unit: "PIXELS", value: 41 };
nomeNave.letterSpacing = { unit: "PIXELS", value: -0.3 };
nomeNave.characters = "Stella Australe";
nomeNave.fills = [paint("inchiostro/primario")];
nomeNave.name = "Nome della nave";
nomi.appendChild(nomeNave);
nomi.appendChild(txt("Sottotitolo schermata", "San Juan → Miami", "inchiostro/secondario"));
eroe.appendChild(nomi);
nomi.x = 24;
nomi.y = 300 - nomi.height - 18;

// Il credito è **la condizione con cui l'autore concede la foto**, quindi deve
// stare sulla foto. In basso a destra: accanto al nome, e dove non copre la barra
// di stato del sistema.
const credito = row(0, { name: "Credito della fotografia" });
pad(credito, 7, 4);
credito.cornerRadius = 100;
credito.fills = [wash("fondo/abisso", 0.7)];
credito.appendChild(txt("Etichetta metrica", "Corey Seeman · CC BY-SA 4.0", "inchiostro/secondario"));
eroe.appendChild(credito);
credito.x = W - credito.width - 12;
credito.y = 300 - credito.height - 14;

try {
  const c = await figma.importComponentByKeyAsync("e01a1714aeec1a5a0a6453485bf16e975008b282");
  const i = c.createInstance();
  i.name = "Barra di stato";
  s.appendChild(i);
  i.x = 0; i.y = 0;
} catch (e) { /* senza la libreria Apple si prosegue: la barra è cosmetica */ }

const contenuto = col(22, { name: "Contenuto" });
pad(contenuto, 24, 0);
contenuto.paddingTop = 28;
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 300;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";
// `resize` blocca **tutt'e due** le dimensioni: senza questa riga la colonna
// resterebbe alta 100 e taglierebbe tutto quello che ci si appende dentro.
contenuto.layoutSizingVertical = "HUG";

const contatore = col(6, { name: "Contatore" });
contatore.counterAxisAlignItems = "CENTER";
const cifreRiga = row(12);
cifreRiga.counterAxisAlignItems = "BASELINE";
const giorni = figma.createText();
giorni.fontName = { family: "SF Pro", style: "Semibold" };
giorni.fontSize = 108;
giorni.letterSpacing = { unit: "PIXELS", value: -1.4 };
giorni.characters = "23";
giorni.fills = [paint("inchiostro/primario")];
giorni.name = "Giorni";
cifreRiga.appendChild(giorni);
const parola = figma.createText();
parola.fontName = { family: "SF Pro", style: "Medium" };
parola.fontSize = 28;
parola.lineHeight = { unit: "PIXELS", value: 34 };
parola.characters = "giorni";
parola.fills = [paint("inchiostro/secondario")];
parola.name = "giorni (parola)";
cifreRiga.appendChild(parola);
contatore.appendChild(cifreRiga);

// Il tono si stringe man mano che la data si avvicina: oltre la settimana è
// «Preparati a salpare», il giorno prima diventa «Domani si parte».
const incoraggiamento = txt("Titolo schermata", "Preparati a salpare.", "accento/azione",
  { name: "Incoraggiamento" });
incoraggiamento.textAlignHorizontal = "CENTER";
contatore.appendChild(incoraggiamento);
contenuto.appendChild(contatore);
contatore.layoutSizingHorizontal = "FILL";

// La card della rotta: **il modo di arrivare alla carta prima di partire**.
// Da quando la testata è la foto, la carta da qui non si raggiungeva più — la
// scheda Carta non c'è più e ci si arriva dalla card, che però in pre-crociera
// non compariva da nessuna parte. Sono i giorni in cui uno la guarda di più: la
// rotta è tutto quello che c'è da vedere finché non sali a bordo.
const cardRotta = figma.createFrame();
cardRotta.name = "La rotta — sostituire con lo screenshot della carta";
cardRotta.resize(W - 48, 196);
cardRotta.clipsContent = true;
cardRotta.cornerRadius = 24;
cardRotta.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: hex(0x0D2C46) },
    { position: 1, color: hex(0x041524) }
  ]
}];
cardRotta.strokes = [paint("bordo/sottile")];
cardRotta.strokeWeight = 0.5;
contenuto.appendChild(cardRotta);
cardRotta.layoutSizingHorizontal = "FILL";
cardRotta.layoutSizingVertical = "FIXED";

// Il velo sotto: serve a staccare le due scritte dal disegno della carta.
const veloRotta = figma.createRectangle();
veloRotta.name = "Velo";
veloRotta.resize(cardRotta.width, 196);
veloRotta.x = 0; veloRotta.y = 0;
veloRotta.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0.5, color: { r: 0, g: 0, b: 0, a: 0 } },
    { position: 1, color: rgba("fondo/abisso", 0.85) }
  ]
}];
cardRotta.appendChild(veloRotta);

const etichettaRotta = txt("Titolo riga", "La rotta", "inchiostro/primario", { name: "La rotta" });
cardRotta.appendChild(etichettaRotta);
etichettaRotta.x = 14;
etichettaRotta.y = 196 - etichettaRotta.height - 14;

// La pastiglia dice **dove ti porta**, non dove sei: è un'azione, non uno stato.
const pastigliaCarta = row(0, { name: "Pastiglia — Carta" });
pad(pastigliaCarta, 10, 5);
pastigliaCarta.cornerRadius = 100;
pastigliaCarta.fills = [wash("fondo/vetro", 0.92)];
pastigliaCarta.strokes = [paint("bordo/sottile")];
pastigliaCarta.strokeWeight = 0.5;
if (ES["Vetro / Chip"]) pastigliaCarta.effectStyleId = ES["Vetro / Chip"].id;
const testoCarta = txt("Etichetta metrica", "Carta", "inchiostro/primario");
testoCarta.fontName = { family: "SF Pro", style: "Semibold" };
pastigliaCarta.appendChild(testoCarta);
cardRotta.appendChild(pastigliaCarta);
pastigliaCarta.x = cardRotta.width - pastigliaCarta.width - 14;
pastigliaCarta.y = 196 - pastigliaCarta.height - 14;

const dettagli = col(12, { name: "Dettagli" });
dettagli.appendChild(infoRow("mappin.and.ellipse", "accento/azione",
  "Imbarco a San Juan", "lun 24 ago · 19:00 · ora di bordo"));
dettagli.appendChild(infoRow("list.bullet.indent", "accento/navigazione",
  "5 scali · 8 notti", "L'itinerario è già pronto nella scheda Itinerario."));

const chipRiga = row(0, { name: "Provenienza" });
chipRiga.paddingTop = 2;
const chip = row(5, { name: "Chip di provenienza" });
chip.counterAxisAlignItems = "CENTER";
pad(chip, 9, 5);
chip.cornerRadius = 100;
chip.fills = [wash("inchiostro/primario", 0.06)];
chip.strokes = [paint("bordo/sottile")];
chip.strokeWeight = 0.5;
chip.appendChild(glifo("calendar", 9, "inchiostro/secondario"));
chip.appendChild(txt("Tecnico", "orario pubblicato", "inchiostro/secondario"));
chipRiga.appendChild(chip);
dettagli.appendChild(chipRiga);

contenuto.appendChild(dettagli);
dettagli.layoutSizingHorizontal = "FILL";
for (const r of dettagli.children) r.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.85 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height, glifiMancanti, stiliRotti };
