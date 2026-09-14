// Preambolo comune a tutti gli script di costruzione delle schermate.
//
// Viene concatenato in testa a ogni corpo da `assembla.py`. Non è un modulo: lo
// script che arriva a `use_figma` dev'essere un blocco solo, autosufficiente.
//
// Regole che questo preambolo fa rispettare da sé, e che sono costate un errore
// ciascuna:
//   · `createAutoLayout` nasce con un riempimento bianco. Su un'app nera copre
//     tutto, quindi `col`/`row` lo tolgono sempre.
//   · L'opacità di un riempimento viene scartata da Figma quando al colore è
//     legata una variabile: dove serve l'alfa si usa `rgba()`, che legge il
//     valore letterale, e si dichiara nel nome del livello.
//   · I glifi si prendono per **nome** SF Symbol, mai per codepoint.

const PAGINA_SCHERMATE = "6:5";
const W = 402, H = 874;              // iPhone 17 Pro, in punti
const MARGINE = 16;                  // il margine orizzontale dell'app

const page = await figma.getNodeByIdAsync(PAGINA_SCHERMATE);
await figma.setCurrentPageAsync(page);

for (const f of [
  { family: "SF Pro", style: "Regular" },
  { family: "SF Pro", style: "Medium" },
  { family: "SF Pro", style: "Semibold" },
  { family: "SF Pro Rounded", style: "Semibold" },
  { family: "Roboto Mono", style: "Medium" }
]) await figma.loadFontAsync(f);

const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));
const TS = Object.fromEntries((await figma.getLocalTextStylesAsync()).map(s => [s.name, s]));
const ES = Object.fromEntries((await figma.getLocalEffectStylesAsync()).map(s => [s.name, s]));

/** Riempimento pieno legato a una variabile colore. */
const paint = (nome) => figma.variables.setBoundVariableForPaint(
  { type: "SOLID", color: { r: 0, g: 0, b: 0 } }, "color", V[nome]);

/** Il valore letterale di una variabile, per quando serve controllare l'alfa. */
const rgba = (nome, a) => {
  const v = V[nome];
  const c = v.valuesByMode[Object.keys(v.valuesByMode)[0]];
  return { r: c.r, g: c.g, b: c.b, a: a === undefined ? (c.a === undefined ? 1 : c.a) : a };
};
/** Riempimento con alfa esplicito: **non** legato, perché il legame lo scarterebbe. */
const wash = (nome, a) => ({ type: "SOLID", color: rgba(nome), opacity: a });

/** Testo con uno stile del sistema applicato. */
const txt = (stile, contenuto, coloreVar, opts) => {
  opts = opts || {};
  const t = figma.createText();
  t.fontName = TS[stile].fontName;
  t.characters = contenuto;
  t.textStyleId = TS[stile].id;
  if (coloreVar) t.fills = [paint(coloreVar)];
  if (opts.upper) t.textCase = "UPPER";
  t.name = opts.name || contenuto.slice(0, 24);
  return t;
};

/** Colonna e riga in auto-layout, senza il bianco predefinito. */
const col = (spacing, opts) => {
  const f = figma.createAutoLayout("VERTICAL", Object.assign({ itemSpacing: spacing }, opts || {}));
  f.fills = [];
  return f;
};
const row = (spacing, opts) => {
  const f = figma.createAutoLayout("HORIZONTAL", Object.assign({ itemSpacing: spacing }, opts || {}));
  f.fills = [];
  return f;
};
const pad = (f, o, v) => {
  f.paddingLeft = f.paddingRight = o;
  f.paddingTop = f.paddingBottom = (v === undefined ? o : v);
  return f;
};

/** Una superficie di vetro, con i numeri di GlassSurface.Prominence. */
const card = (raggio, tinta) => {
  const f = col(0);
  f.fills = tinta ? [wash(tinta, 0.10), wash("fondo/vetro", 1)] : [paint("fondo/vetro")];
  if (tinta) f.fills = [wash("fondo/vetro", 1), wash(tinta, 0.12)];
  f.strokes = [paint("bordo/sottile")];
  f.strokeWeight = 0.5;
  f.cornerRadius = raggio;
  if (ES["Vetro / Card"]) f.effectStyleId = ES["Vetro / Card"].id;
  return f;
};

/** Un glifo SF Symbol, per nome. */
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  t.characters = figma.util.getSfSymbolCharacter(nome);
  t.name = "icona/" + nome;
  if (coloreVar) t.fills = [paint(coloreVar)];
  return t;
};

/** La riga di grandezze: valore sopra, etichetta sotto, colonne uguali. */
const grandezze = (elenco) => {
  const r = row(12);
  r.counterAxisAlignItems = "MIN";
  for (const [valore, etichetta] of elenco) {
    const c = col(3);
    c.appendChild(txt("Valore metrica", valore, "inchiostro/primario"));
    c.appendChild(txt("Etichetta metrica", etichetta, "inchiostro/terziario", { upper: true }));
    r.appendChild(c);
    c.layoutSizingHorizontal = "FILL";
  }
  return r;
};

/** Un filo orizzontale: un tratto, non un rettangolo alto un punto. */
const filo = () => {
  const l = figma.createLine();
  l.strokes = [paint("bordo/sottile")];
  l.strokeWeight = 0.5;
  l.name = "filo";
  return l;
};

/** La cornice della schermata, col gradiente a tre fermate dell'app. */
const schermata = (nome, x, fermate) => {
  const s = figma.createFrame();
  s.name = nome;
  s.resize(W, H);
  s.x = x; s.y = 0;
  s.clipsContent = true;
  s.layoutMode = "NONE";
  s.fills = [{
    type: "GRADIENT_LINEAR",
    // Dall'alto verso il basso.
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: fermate.map((f, i) => ({
      position: i / (fermate.length - 1),
      color: typeof f === "string" ? rgba(f) : f
    }))
  }];
  return s;
};

/** La barra di stato di Apple, con ripiego se la libreria non risponde. */
const barraDiStato = async () => {
  try {
    const c = await figma.importComponentByKeyAsync("e01a1714aeec1a5a0a6453485bf16e975008b282");
    const i = c.createInstance();
    i.name = "Barra di stato";
    return i;
  } catch (e) {
    const f = row(0, { name: "Barra di stato (ripiego)" });
    f.resize(W, 59);
    const t = txt("Titolo riga", "11:53", "inchiostro/primario");
    f.appendChild(t);
    pad(f, 28, 18);
    return f;
  }
};

/** La barra delle schede: cinque coppie glifo+parola su una pastiglia di vetro.
 *  Costruita a mano e non presa da Apple perché i cinque glifi e le cinque
 *  parole sono di Cruisy: il componente di sistema andrebbe comunque riscritto. */
const barraSchede = (attiva) => {
  const schede = [
    ["Oggi", "sun.horizon"],
    ["Carta", "location.north.line"],
    ["Itinerario", "list.bullet.indent"],
    ["Nave", "ferry"],
    ["Diario", "book.closed"]
  ];
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
    if (scelta) {
      c.cornerRadius = 26;
      c.fills = [wash("accento/navigazione", 0.14)];
    }
    c.appendChild(glifo(simbolo, 20, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    c.appendChild(txt("Etichetta metrica", nome,
      scelta ? "accento/navigazione" : "inchiostro/secondario"));
    barra.appendChild(c);
  }
  return barra;
};

// --- Itinerario ------------------------------------------------------------
// Nove righe: sette scali e due giorni di mare. Le righe si somigliano, quindi
// si costruisce **un componente** e si posano istanze — non nove riquadri quasi
// uguali.

const s = schermata("Itinerario", 920,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const contenuto = col(10, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 59;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

// --- testata ---------------------------------------------------------------
const testata = row(12, { name: "Testata" });
testata.counterAxisAlignItems = "CENTER";
const nomi = col(2);
nomi.counterAxisAlignItems = "CENTER";
nomi.appendChild(txt("Titolo schermata", "Stella Australe", "inchiostro/primario"));
nomi.appendChild(txt("Sottotitolo schermata", "8 notti · 5 scali", "inchiostro/secondario"));
testata.appendChild(nomi);
const modifica = row(0, { name: "Modifica" });
pad(modifica, 14, 8);
modifica.cornerRadius = 100;
modifica.fills = [wash("inchiostro/primario", 0.08)];
modifica.strokes = [paint("bordo/sottile")];
modifica.strokeWeight = 0.5;
modifica.appendChild(txt("Titolo riga", "Modifica", "accento/azione"));
testata.appendChild(modifica);
contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";
testata.primaryAxisAlignItems = "SPACE_BETWEEN";

// --- il componente riga ----------------------------------------------------
// Una riga sola, con le proprietà di testo esposte: il resto sono istanze.
const modello = figma.createComponent();
modello.name = "Riga di scalo";
modello.description =
  "Una tappa dell'itinerario. Il giorno a sinistra, il porto e la finestra a destra. " +
  "Il filo verticale è continuo per uno scalo e tratteggiato per un giorno di mare: " +
  "la differenza non è affidata al solo colore.";
modello.layoutMode = "HORIZONTAL";
modello.itemSpacing = 12;
modello.counterAxisAlignItems = "CENTER";
modello.primaryAxisSizingMode = "AUTO";
modello.counterAxisSizingMode = "AUTO";
pad(modello, 14, 14);
modello.cornerRadius = 20;
modello.fills = [paint("fondo/vetro")];
modello.strokes = [paint("bordo/sottile")];
modello.strokeWeight = 0.5;
if (ES["Vetro / Card"]) modello.effectStyleId = ES["Vetro / Card"].id;
modello.resize(370, 76);
modello.layoutSizingHorizontal = "FIXED";

const giorno = col(0, { name: "Giorno" });
giorno.counterAxisAlignItems = "CENTER";
giorno.resize(52, 44);
const giornoSett = txt("Etichetta metrica", "GIO", "inchiostro/terziario", { name: "Settimana" });
const giornoNum = txt("Titolo schermata", "27", "inchiostro/primario", { name: "Numero" });
giorno.appendChild(giornoSett);
giorno.appendChild(giornoNum);
modello.appendChild(giorno);
giorno.layoutSizingHorizontal = "FIXED";

const separatore = figma.createRectangle();
separatore.name = "Filo";
separatore.resize(2, 40);
separatore.cornerRadius = 1;
separatore.fills = [wash("inchiostro/primario", 0.22)];
modello.appendChild(separatore);

const dettagli = col(3, { name: "Dettagli" });
const porto = txt("Titolo riga", "San Juan", "inchiostro/primario", { name: "Porto" });
const finestra = txt("Dettaglio riga", "14:00 → 20:00 · banchina", "inchiostro/secondario", { name: "Finestra" });
dettagli.appendChild(porto);
dettagli.appendChild(finestra);
modello.appendChild(dettagli);
dettagli.layoutSizingHorizontal = "FILL";

const freccia = glifo("chevron.right", 13, "inchiostro/terziario");
modello.appendChild(freccia);

modello.x = -600; modello.y = 0;   // il modello sta fuori dalla schermata
page.appendChild(modello);

// Proprietà di testo: è così che le istanze si riempiono senza staccarsi.
const pSett = modello.addComponentProperty("Settimana", "TEXT", "GIO");
const pNum = modello.addComponentProperty("Numero", "TEXT", "27");
const pPorto = modello.addComponentProperty("Porto", "TEXT", "San Juan");
const pFinestra = modello.addComponentProperty("Finestra", "TEXT", "14:00 → 20:00 · banchina");
giornoSett.componentPropertyReferences = { characters: pSett };
giornoNum.componentPropertyReferences = { characters: pNum };
porto.componentPropertyReferences = { characters: pPorto };
finestra.componentPropertyReferences = { characters: pFinestra };

// --- le nove righe ---------------------------------------------------------
const tappe = [
  ["GIO", "27", "San Juan", "14:00 → 20:00 · banchina", "scalo"],
  ["VEN", "28", "Charlotte Amalie", "07:00 → 16:00 · banchina", "scalo"],
  ["SAB", "29", "Gustavia", "08:00 → 18:00 · tender", "scalo"],
  ["DOM", "30", "Giorno di mare", "Verso Puerto Plata · 460 mn", "mare"],
  ["LUN", "31", "Puerto Plata", "09:00 → 18:00 · banchina", "oggi"],
  ["MAR", "1", "Grand Turk", "08:00 → 17:00 · banchina", "domani"],
  ["MER", "2", "Giorno di mare", "Verso Nassau · 405 mn", "mare"],
  ["GIO", "3", "Nassau", "07:00 → 14:00 · banchina", "scalo"],
  ["VEN", "4", "Miami", "07:00 · banchina", "scalo"]
];

const istanze = [];
for (const [sett, num, nome, finestraTesto, tipo] of tappe) {
  const i = modello.createInstance();
  i.setProperties({
    [pSett]: sett, [pNum]: num, [pPorto]: nome, [pFinestra]: finestraTesto
  });
  i.name = nome;

  // Oggi si distingue con colore **e** parola, mai col solo colore.
  if (tipo === "oggi" || tipo === "domani") {
    const accento = tipo === "oggi" ? "accento/porto" : "accento/porto";
    i.fills = [wash("fondo/vetro", 1), wash(accento, 0.14)];
    const filoVerticale = i.findOne(n => n.name === "Filo");
    if (filoVerticale) filoVerticale.fills = [paint(accento)];
    const etichetta = i.findOne(n => n.name === "Numero");
    if (etichetta) etichetta.fills = [paint(accento)];
  }
  if (tipo === "mare") {
    const filoVerticale = i.findOne(n => n.name === "Filo");
    if (filoVerticale) filoVerticale.fills = [wash("accento/navigazione", 0.45)];
  }

  contenuto.appendChild(i);
  i.layoutSizingHorizontal = "FILL";
  istanze.push(i.id);
}

const barra = barraSchede("Itinerario");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 1 });
return {
  createdNodeIds: [s.id, modello.id].concat(istanze),
  schermata: s.id,
  componenteRiga: modello.id,
  altezzaContenuto: contenuto.height
};
