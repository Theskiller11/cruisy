#!/usr/bin/env python3
"""Concatena il preambolo con ciascun corpo e scrive gli script pronti in `out/`.

`use_figma` accetta un blocco di codice solo, quindi ogni script dev'essere
autosufficiente. Tenere il preambolo in un file a parte evita di correggere lo
stesso errore in cinque posti.

Uso:  python3 figma/assembla.py
"""
import pathlib, sys

qui = pathlib.Path(__file__).parent
out = qui / "out"
out.mkdir(exist_ok=True)

preambolo = (qui / "_preambolo.js").read_text()
scritti = []

for corpo in sorted(qui.glob("[0-9][0-9]-*.js")):
    testo = corpo.read_text()
    # Il fix delle pastiglie non tocca la pagina Schermate: va da solo.
    completo = testo if corpo.name.startswith("00-") else preambolo + "\n" + testo
    destinazione = out / corpo.name
    destinazione.write_text(completo)
    scritti.append((corpo.name, len(completo)))

for nome, n in scritti:
    print(f"  {nome:24s} {n:6d} caratteri" + ("  ⚠ oltre il limite di 50.000" if n > 50000 else ""))
print(f"\n{len(scritti)} script in {out}")
