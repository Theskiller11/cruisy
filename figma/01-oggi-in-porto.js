// --- Oggi, giorno di porto -------------------------------------------------
// La schermata che conta: un numero solo, quello che manca al rientro a bordo.

const s = schermata("Oggi — in porto", 0,
  ["fondo/porto-alto", { r: 11/255, g: 23/255, b: 37/255, a: 1 }, "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

// Colonna del contenuto: margine 16, passo 12, come nell'app.
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
nomi.appendChild(txt("Sottotitolo schermata", "Giorno 5 di 9", "inchiostro/secondario"));
testata.appendChild(nomi);

const pastiglia = row(6, { name: "Pastiglia di stato" });
pastiglia.counterAxisAlignItems = "CENTER";
pad(pastiglia, 11, 6);
pastiglia.cornerRadius = 100;
pastiglia.fills = [wash("accento/porto", 0.16)];
pastiglia.strokes = [paint("bordo/sottile")];
pastiglia.strokeWeight = 0.5;
pastiglia.appendChild(glifo("ferry", 11, "accento/porto"));
pastiglia.appendChild(txt("Etichetta metrica", "In porto", "accento/porto"));
testata.appendChild(pastiglia);

contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";

// --- avviso sull'ora di bordo ----------------------------------------------
// Sta qui perché è così che si perde la nave: il telefono si riallinea da solo,
// la nave no.
const avviso = card(20, "accento/porto");
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

// --- l'eroe: il countdown all'all aboard -----------------------------------
const eroe = card(24, "accento/porto");
pad(eroe, 16, 16);
eroe.itemSpacing = 14;
eroe.name = "Rientro a bordo";

const eroeTesta = row(8);
eroeTesta.counterAxisAlignItems = "CENTER";
eroeTesta.appendChild(txt("Eyebrow", "Puerto Plata", "accento/porto", { upper: true }));
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
eroeTesta.primaryAxisAlignItems = "SPACE_BETWEEN";

// L'anello si riempie da **attracco a all aboard**, lo stesso evento del numero
// che abbraccia. Il brief lo faceva misurare la sosta: un anello e un numero che
// contano cose diverse chiedono a chi guarda di scegliere.
const anello = figma.createFrame();
anello.name = "Anello";
anello.resize(232, 232);
anello.fills = [];
anello.clipsContent = false;

const SPESSORE = 10, RAGGIO = 116;
const traccia = figma.createEllipse();
traccia.resize(232, 232);
traccia.x = 0; traccia.y = 0;
traccia.fills = [wash("inchiostro/primario", 0.16)];
traccia.strokes = [];
traccia.arcData = { startingAngle: 0, endingAngle: 2 * Math.PI, innerRadius: (RAGGIO - SPESSORE) / RAGGIO };
traccia.name = "traccia";
anello.appendChild(traccia);

const arco = figma.createEllipse();
arco.resize(232, 232);
arco.x = 0; arco.y = 0;
arco.fills = [paint("accento/porto")];
arco.strokes = [];
arco.arcData = {
  startingAngle: -Math.PI / 2,
  endingAngle: -Math.PI / 2 + 2 * Math.PI * 0.68,
  innerRadius: (RAGGIO - SPESSORE) / RAGGIO
};
arco.name = "avanzamento";
anello.appendChild(arco);

const dentro = col(4, { name: "Dentro l'anello" });
dentro.counterAxisAlignItems = "CENTER";
dentro.appendChild(txt("Eyebrow", "Rientro a bordo", "inchiostro/secondario", { upper: true }));
const cifre = txt("Display / Countdown", "2:59:52", "inchiostro/primario");
dentro.appendChild(cifre);
dentro.appendChild(txt("Dettaglio riga", "entro le 17:30", "inchiostro/secondario"));
anello.appendChild(dentro);
dentro.x = (232 - dentro.width) / 2;
dentro.y = (232 - dentro.height) / 2;

const anelloBox = row(0, { name: "Anello (centrato)" });
anelloBox.primaryAxisAlignItems = "CENTER";
anelloBox.appendChild(anello);
eroe.appendChild(anelloBox);
anelloBox.layoutSizingHorizontal = "FILL";

const f1 = filo();
eroe.appendChild(f1);
f1.layoutSizingHorizontal = "FILL";

eroe.appendChild(grandezze([
  ["09:00", "Attracco"], ["18:00", "Partenza"], ["9h", "Sosta"]
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
const cartaPiede = row(8, { name: "Piede della carta" });
cartaPiede.counterAxisAlignItems = "CENTER";
cartaPiede.primaryAxisAlignItems = "SPACE_BETWEEN";
pad(cartaPiede, 14, 12);
cartaPiede.appendChild(txt("Titolo riga", "Puerto Plata", "inchiostro/primario"));
const bottoneCarta = row(0, { name: "Carta" });
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
mareTesta.appendChild(txt("Eyebrow", "In porto", "inchiostro/terziario", { upper: true }));
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
mareTesti.appendChild(txt("Titolo schermata", "Molto mosso", "inchiostro/primario"));
mareTesti.appendChild(txt("Dettaglio riga", "Beccheggio avvertibile", "inchiostro/secondario"));
mareRiga.appendChild(mareTesti);
const gradi = txt("Display / Totale", "30°", "inchiostro/primario");
mareRiga.appendChild(gradi);
mare.appendChild(mareRiga);
mareRiga.layoutSizingHorizontal = "FILL";
mareTesti.layoutSizingHorizontal = "FILL";

const f2 = filo();
mare.appendChild(f2);
f2.layoutSizingHorizontal = "FILL";
mare.appendChild(grandezze([["1,4 m", "Onda"], ["6 kn NE", "Vento"], ["30°", "Acqua"]]));
mare.children[mare.children.length - 1].layoutSizingHorizontal = "FILL";

contenuto.appendChild(mare);
mare.layoutSizingHorizontal = "FILL";

// --- la barra delle schede -------------------------------------------------
const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
