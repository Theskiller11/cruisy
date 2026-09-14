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

await s.screenshot({ scale: 0.75 });
return {
  createdNodeIds: [s.id, modello.id].concat(istanze),
  schermata: s.id,
  componenteRiga: modello.id,
  altezzaContenuto: contenuto.height
};
