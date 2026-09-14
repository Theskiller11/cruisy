// Porta al 16% l'opacità del riempimento delle quattro Pastiglie di stato.
//
// Erano piene al 100%, e il testo sopra — dello stesso accento — spariva.
// Lo script prova prima la strada pulita (riempimento legato alla variabile con
// opacità abbassata) e, se Figma la scarta, ripiega sul colore letterale e lo
// dichiara nel valore di ritorno invece di lasciarlo scoprire a qualcun altro.

const paginaComponenti = await figma.getNodeByIdAsync("6:4");
await figma.setCurrentPageAsync(paginaComponenti);

const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));

const accenti = {
  "10:5":  "accento/azione",       // Prima dell'imbarco
  "10:8":  "accento/porto",        // In porto
  "10:11": "accento/navigazione",  // Giorno di mare
  "10:14": "accento/azione"        // Sbarcati
};

const esito = [];
for (const id of Object.keys(accenti)) {
  const n = await figma.getNodeByIdAsync(id);
  n.fills = n.fills.map(f => Object.assign({}, f, { opacity: 0.16 }));

  if (n.fills[0].opacity !== 0.16) {
    const v = V[accenti[id]];
    const c = v.valuesByMode[Object.keys(v.valuesByMode)[0]];
    n.fills = [{ type: "SOLID", color: { r: c.r, g: c.g, b: c.b }, opacity: 0.16 }];
  }

  esito.push({
    id,
    opacita: n.fills[0].opacity,
    legataAllaVariabile: !!(n.fills[0].boundVariables && n.fills[0].boundVariables.color)
  });
}

const set = await figma.getNodeByIdAsync("10:17");
await set.screenshot({ scale: 3 });

return { mutatedNodeIds: Object.keys(accenti), esito };
