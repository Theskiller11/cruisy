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
  // Il vetro sotto, la tinta sopra: l'ordine conta, e la seconda assegnazione
  // che c'era prima cancellava la prima senza dirlo.
  f.fills = tinta ? [wash("fondo/vetro", 1), wash(tinta, 0.12)] : [paint("fondo/vetro")];
  f.strokes = [paint("bordo/sottile")];
  f.strokeWeight = 0.5;
  f.cornerRadius = raggio;
  if (ES["Vetro / Card"]) f.effectStyleId = ES["Vetro / Card"].id;
  return f;
};

/** Un glifo SF Symbol, per nome.
 *
 *  Se il convertitore non conosce il nome lancia `RangeError`. In uno script che
 *  costruisce cinque schermate, un solo nome ignoto le farebbe fallire tutte e
 *  cinque: qui si segna il buco e si prosegue, invece di perdere tutto per
 *  un'icona. I nomi mancanti tornano nel valore di ritorno, così si vedono. */
const glifiMancanti = [];
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  try {
    t.characters = figma.util.getSfSymbolCharacter(nome);
  } catch (e) {
    if (glifiMancanti.indexOf(nome) < 0) glifiMancanti.push(nome);
    t.characters = "\u25CF";
  }
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
