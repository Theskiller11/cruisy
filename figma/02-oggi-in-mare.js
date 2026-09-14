// --- Oggi, giorno di mare --------------------------------------------------
// Stessa struttura della schermata in porto, ma l'evento cambia: si conta
// all'arrivo, e l'avanzamento è un'onda invece di un anello.

const s = schermata("Oggi — in mare", 460,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const contenuto = col(12, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 59;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

// --- testata ---------------------------------------------------------------
const testata = row(12, { name: "Testata" });
testata.counterAxisAlignItems = "CENTER";
const nomi = col(2);
nomi.appendChild(txt("Titolo schermata", "Stella Australe", "inchiostro/primario"));
nomi.appendChild(txt("Sottotitolo schermata", "Giorno 4 di 9", "inchiostro/secondario"));
testata.appendChild(nomi);

const pastiglia = row(6, { name: "Pastiglia di stato" });
pastiglia.counterAxisAlignItems = "CENTER";
pad(pastiglia, 11, 6);
pastiglia.cornerRadius = 100;
pastiglia.fills = [wash("accento/navigazione", 0.16)];
pastiglia.strokes = [paint("bordo/sottile")];
pastiglia.strokeWeight = 0.5;
pastiglia.appendChild(glifo("water.waves", 11, "accento/navigazione"));
pastiglia.appendChild(txt("Etichetta metrica", "Giorno di mare", "accento/navigazione"));
testata.appendChild(pastiglia);

contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";

// --- avviso sull'ora di bordo ----------------------------------------------
const avviso = card(20);
pad(avviso, 14, 12);
const avvisoRiga = row(10);
avvisoRiga.counterAxisAlignItems = "CENTER";
avvisoRiga.appendChild(glifo("exclamationmark.triangle.fill", 13, "accento/porto"));
const avvisoTesto = txt("Dettaglio riga",
  "Il telefono è 6 ore avanti rispetto all'ora di bordo. Gli orari qui sono in ora di bordo.",
  "inchiostro/secondario");
avvisoTesto.textAutoResize = "HEIGHT";
avvisoRiga.appendChild(avvisoTesto);
avviso.appendChild(avvisoRiga);
contenuto.appendChild(avviso);
avviso.layoutSizingHorizontal = "FILL";
avvisoRiga.layoutSizingHorizontal = "FILL";
avvisoTesto.layoutSizingHorizontal = "FILL";

// --- l'eroe: la traversata -------------------------------------------------
const eroe = card(24, "accento/navigazione");
pad(eroe, 16, 16);
eroe.itemSpacing = 10;
eroe.name = "Traversata";

const eroeTesta = row(8);
eroeTesta.primaryAxisAlignItems = "SPACE_BETWEEN";
eroeTesta.counterAxisAlignItems = "CENTER";
const statoRiga = row(6);
statoRiga.counterAxisAlignItems = "CENTER";
statoRiga.appendChild(glifo("water.waves", 12, "accento/navigazione"));
statoRiga.appendChild(txt("Titolo riga", "In navigazione", "accento/navigazione"));
eroeTesta.appendChild(statoRiga);
const chip = row(5, { name: "Chip di provenienza" });
chip.counterAxisAlignItems = "CENTER";
pad(chip, 9, 5);
chip.cornerRadius = 100;
chip.fills = [wash("inchiostro/primario", 0.06)];
chip.strokes = [paint("bordo/sottile")];
chip.strokeWeight = 0.5;
chip.appendChild(glifo("calendar", 9, "inchiostro/secondario"));
chip.appendChild(txt("Tecnico", "orario pubblicato", "inchiostro/secondario"));
eroeTesta.appendChild(chip);
eroe.appendChild(eroeTesta);
eroeTesta.layoutSizingHorizontal = "FILL";

eroe.appendChild(txt("Dettaglio riga", "All'arrivo a Puerto Plata", "inchiostro/secondario"));

const cifreRiga = row(8);
cifreRiga.counterAxisAlignItems = "BASELINE";
cifreRiga.appendChild(txt("Display / Countdown", "19:29:52", "inchiostro/primario"));
cifreRiga.appendChild(txt("Etichetta metrica", "h · m · s", "inchiostro/terziario"));
eroe.appendChild(cifreRiga);

eroe.appendChild(txt("Dettaglio riga", "previsto lun 31 ago · 09:00", "inchiostro/secondario"));

// L'onda: traccia e parte percorsa disegnate dalla **stessa** forma. Erano due
// onde con fasi diverse, e combaciavano solo ogni tanto.
const onda = figma.createFrame();
onda.name = "Avanzamento — onda";
onda.resize(340, 14);
onda.fills = [];
onda.clipsContent = true;
const d = (() => {
  let p = "M 0 7";
  for (let x = 0; x <= 340; x += 10) {
    p += " Q " + (x + 5) + " " + (7 + (x / 10 % 2 === 0 ? -5 : 5)) + " " + (x + 10) + " 7";
  }
  return p;
})();
const ondaTraccia = figma.createVector();
ondaTraccia.vectorPaths = [{ windingRule: "NONE", data: d }];
ondaTraccia.strokes = [wash("inchiostro/primario", 0.18)];
ondaTraccia.strokeWeight = 4;
ondaTraccia.strokeCap = "ROUND";
ondaTraccia.fills = [];
ondaTraccia.name = "traccia";
onda.appendChild(ondaTraccia);
ondaTraccia.x = 0; ondaTraccia.y = 0;

// La parte percorsa è la **stessa** onda, ritagliata da un riquadro. Erano due
// onde con fasi diverse, e combaciavano solo ogni tanto. Un riquadro che
// ritaglia è più prevedibile di una maschera, che dipende dall'ordine dei livelli.
const ritaglio = figma.createFrame();
ritaglio.name = "percorso (ritagliato)";
ritaglio.resize(150, 14);
ritaglio.x = 0; ritaglio.y = 0;
ritaglio.fills = [];
ritaglio.clipsContent = true;
onda.appendChild(ritaglio);

const ondaFatta = figma.createVector();
ondaFatta.vectorPaths = [{ windingRule: "NONE", data: d }];
ondaFatta.strokes = [paint("accento/navigazione")];
ondaFatta.strokeWeight = 4;
ondaFatta.strokeCap = "ROUND";
ondaFatta.fills = [];
ondaFatta.name = "percorso";
ritaglio.appendChild(ondaFatta);
ondaFatta.x = 0; ondaFatta.y = 0;

const ondaBox = row(0);
ondaBox.appendChild(onda);
eroe.appendChild(ondaBox);
ondaBox.layoutSizingHorizontal = "FILL";

const porti = row(8);
porti.primaryAxisAlignItems = "SPACE_BETWEEN";
porti.appendChild(txt("Dettaglio riga", "Gustavia", "inchiostro/secondario"));
porti.appendChild(txt("Dettaglio riga", "Puerto Plata", "inchiostro/secondario"));
eroe.appendChild(porti);
porti.layoutSizingHorizontal = "FILL";

const f1 = filo();
eroe.appendChild(f1);
f1.layoutSizingHorizontal = "FILL";
eroe.appendChild(grandezze([
  ["11,8 kt", "Velocità"], ["284°", "Rotta"], ["230 mn", "Alla meta"]
]));
eroe.children[eroe.children.length - 1].layoutSizingHorizontal = "FILL";

contenuto.appendChild(eroe);
eroe.layoutSizingHorizontal = "FILL";

// --- la carta --------------------------------------------------------------
const carta = card(24);
carta.name = "Carta";
carta.clipsContent = true;
const cartaBox = figma.createFrame();
cartaBox.name = "Disegno della carta — sostituire con lo screenshot";
cartaBox.resize(370, 200);
cartaBox.fills = [wash("fondo/mare-alto", 1)];
carta.appendChild(cartaBox);
const cartaPiede = row(8);
cartaPiede.counterAxisAlignItems = "CENTER";
cartaPiede.primaryAxisAlignItems = "SPACE_BETWEEN";
pad(cartaPiede, 14, 12);
cartaPiede.appendChild(txt("Titolo riga", "Verso Puerto Plata", "inchiostro/primario"));
const bottoneCarta = row(0);
pad(bottoneCarta, 12, 7);
bottoneCarta.cornerRadius = 100;
bottoneCarta.fills = [wash("inchiostro/primario", 0.10)];
bottoneCarta.appendChild(txt("Dettaglio riga", "Carta", "inchiostro/primario"));
cartaPiede.appendChild(bottoneCarta);
carta.appendChild(cartaPiede);
contenuto.appendChild(carta);
carta.layoutSizingHorizontal = "FILL";
cartaBox.layoutSizingHorizontal = "FILL";
cartaPiede.layoutSizingHorizontal = "FILL";

// --- lo stato del mare -----------------------------------------------------
const mare = card(24);
mare.name = "Stato del mare";
pad(mare, 16, 16);
mare.itemSpacing = 12;
const mareTesta = row(8);
mareTesta.primaryAxisAlignItems = "SPACE_BETWEEN";
mareTesta.counterAxisAlignItems = "CENTER";
mareTesta.appendChild(txt("Eyebrow", "Mare", "inchiostro/terziario", { upper: true }));
const fresco = row(5);
fresco.counterAxisAlignItems = "CENTER";
fresco.appendChild(glifo("checkmark.circle", 11, "inchiostro/terziario"));
fresco.appendChild(txt("Etichetta metrica", "aggiornato", "inchiostro/terziario"));
mareTesta.appendChild(fresco);
mare.appendChild(mareTesta);
mareTesta.layoutSizingHorizontal = "FILL";

const mareRiga = row(12);
mareRiga.counterAxisAlignItems = "CENTER";
mareRiga.appendChild(glifo("cloud.sun.fill", 26, "inchiostro/primario", "Regular"));
const mareTesti = col(2);
mareTesti.appendChild(txt("Titolo schermata", "Mosso", "inchiostro/primario"));
mareTesti.appendChild(txt("Dettaglio riga", "Movimento appena percettibile", "inchiostro/secondario"));
mareRiga.appendChild(mareTesti);
mareRiga.appendChild(txt("Display / Totale", "24°", "inchiostro/primario"));
mare.appendChild(mareRiga);
mareRiga.layoutSizingHorizontal = "FILL";
mareTesti.layoutSizingHorizontal = "FILL";

const f2 = filo();
mare.appendChild(f2);
f2.layoutSizingHorizontal = "FILL";
mare.appendChild(grandezze([["1,0 m", "Onda"], ["8 kn SE", "Vento"], ["29°", "Acqua"]]));
mare.children[mare.children.length - 1].layoutSizingHorizontal = "FILL";
contenuto.appendChild(mare);
mare.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
