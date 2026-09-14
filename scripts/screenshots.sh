#!/usr/bin/env bash
# Fotografa tutte le schermate di Cruisy sul simulatore, senza toccare lo schermo.
#
# Perché esiste: su questo Mac non c'è Simulator.app e il pannello del simulatore di
# Claude Code cade. `simctl` sa avviare e fotografare, non toccare. Gli argomenti
# DEBUG `-sample`, `-tab` e `-open` (vedi Cruisy/Services/DebugLaunch.swift) portano
# l'app dritta in ogni schermata, e questo script le passa in rassegna tutte.
#
# Uso:
#   scripts/screenshots.sh                     # tutte, in italiano, corpo normale
#   scripts/screenshots.sh --lang en           # in inglese
#   scripts/screenshots.sh --size AX5          # corpo accessibile più grande
#   scripts/screenshots.sh --only diario,porti # solo alcune
#   scripts/screenshots.sh --no-build          # riusa l'ultima build
#   scripts/screenshots.sh --out /percorso     # cartella di uscita
#
# Esce con una cartella di PNG e un `foglio.jpg` con tutte le schermate affiancate,
# che si guarda in un colpo solo.

set -euo pipefail

cd "$(dirname "$0")/.."

LANG_CODE="it"
SIZE="default"
ONLY=""
BUILD=1
DEVICE="${SIMULATOR:-iPhone 17 Pro}"
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_CODE="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
  esac
done

case "$LANG_CODE" in
  it) LOCALE="it_IT" ;;
  en) LOCALE="en_US" ;;
  *) LOCALE="${LANG_CODE}_$(echo "$LANG_CODE" | tr '[:lower:]' '[:upper:]')" ;;
esac

# I corpi del testo come li chiama simctl.
case "$SIZE" in
  default) CATEGORY="large" ;;
  XS) CATEGORY="extra-small" ;;
  XL) CATEGORY="extra-large" ;;
  XXXL) CATEGORY="extra-extra-extra-large" ;;
  AX1) CATEGORY="accessibility-medium" ;;
  AX3) CATEGORY="accessibility-extra-large" ;;
  AX5) CATEGORY="accessibility-extra-extra-extra-large" ;;
  *) CATEGORY="$SIZE" ;;
esac

OUT="${OUT:-screenshots/$(date +%Y%m%d-%H%M%S)-$LANG_CODE-$SIZE}"
mkdir -p "$OUT"

# nome | attesa in secondi | argomenti di avvio
# L'attesa è più lunga dove l'app scarica una foto o il meteo.
SHOTS=(
  "oggi-porto|5|-sample inPort -tab oggi"
  "oggi-mare|5|-sample atSea -tab oggi"
  "oggi-imminente|5|-sample imminent -tab oggi"
  "imbarco-domani|5|-sample beforeBoarding -tab oggi"
  "pre-crociera|6|-sample farFromBoarding -tab oggi"
  "carta-porto|6|-sample inPort -open carta"
  "carta-mare|6|-sample atSea -open carta"
  "itinerario|10|-sample inPort -tab itinerario"
  "scalo|8|-sample inPort -open scalo"
  "nave|8|-sample inPort -tab nave"
  "diario|5|-sample inPort -tab diario"
  "porti|10|-sample inPort -open porti"
  "editor|5|-sample inPort -open editor"
  "importazione|5|-sample inPort -open importazione"
  "impostazioni|5|-sample inPort -open impostazioni"
  "onboarding|5|-sample inPort -open onboarding"
)

UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [[ -z "$UDID" ]]; then echo "nessun simulatore chiamato «$DEVICE»" >&2; exit 1; fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

if [[ $BUILD -eq 1 ]]; then
  echo "compilo…"
  xcodebuild -scheme Cruisy -destination "platform=iOS Simulator,id=$UDID" build -quiet
fi
APP=$(xcodebuild -scheme Cruisy -destination "platform=iOS Simulator,id=$UDID" -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Cruisy.app
xcrun simctl install "$UDID" "$APP"

# Barra di stato pulita e sempre uguale: le differenze fra due giri devono essere
# dell'app, non dell'orologio o della batteria.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --wifiBars 3 --cellularMode notSupported >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size "$CATEGORY"
trap 'xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true' EXIT

for entry in "${SHOTS[@]}"; do
  IFS='|' read -r name wait args <<< "$entry"
  if [[ -n "$ONLY" && ",$ONLY," != *",$name,"* ]]; then continue; fi
  xcrun simctl terminate "$UDID" it.matteopapini.Cruisy >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  xcrun simctl launch "$UDID" it.matteopapini.Cruisy $args \
    -cruisy.hasSeenDisclaimer YES -cruisy.wantsTracking NO \
    -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "  $name"
done
xcrun simctl terminate "$UDID" it.matteopapini.Cruisy >/dev/null 2>&1 || true

# Il foglio: tutte le schermate in una griglia da quattro colonne, ridotte.
swift - "$OUT" <<'SWIFT'
import AppKit
let dir = CommandLine.arguments[1]
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
    .filter { $0.hasSuffix(".png") }.sorted() ?? []
guard !files.isEmpty else { exit(0) }
let w: CGFloat = 300, h: CGFloat = 652, label: CGFloat = 28, gap: CGFloat = 16, cols = 4
let rows = (files.count + cols - 1) / cols
let size = NSSize(width: CGFloat(cols) * (w + gap) + gap, height: CGFloat(rows) * (h + label + gap) + gap)
let sheet = NSImage(size: size)
sheet.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
for (i, file) in files.enumerated() {
    let col = CGFloat(i % cols), row = CGFloat(i / cols)
    let x = gap + col * (w + gap)
    let y = size.height - (gap + (row + 1) * (h + label + gap)) + gap
    NSImage(contentsOfFile: dir + "/" + file)?.draw(in: NSRect(x: x, y: y + label, width: w, height: h))
    let name = (file as NSString).deletingPathExtension as NSString
    name.draw(at: NSPoint(x: x, y: y + 6), withAttributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white])
}
sheet.unlockFocus()
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
    .write(to: URL(fileURLWithPath: dir + "/foglio.jpg"))
SWIFT

echo "fatto: $OUT (foglio.jpg per vederle tutte)"
