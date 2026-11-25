#!/usr/bin/env bash
# Descarga Tesseract.js (lector de texto para la versión web) y el idioma
# español desde el registro de npm, y los deja en web/tesseract/.
# Se ejecuta antes de «flutter build web» (lo hace el flujo de GitHub).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=web/tesseract
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fetch() { curl -sSfL "https://registry.npmjs.org/$1" -o "$TMP/pkg.tgz"; rm -rf "$TMP/package"; tar xzf "$TMP/pkg.tgz" -C "$TMP"; }
mkdir -p "$DEST/core" "$DEST/lang"
fetch "tesseract.js/-/tesseract.js-7.0.0.tgz"
cp "$TMP/package/dist/tesseract.min.js" "$TMP/package/dist/worker.min.js" "$DEST/"
fetch "tesseract.js-core/-/tesseract.js-core-7.0.0.tgz"
cp "$TMP"/package/tesseract-core*lstm.wasm.js "$DEST/core/"
fetch "@tesseract.js-data/spa/-/spa-1.0.0.tgz"
cp "$TMP/package/4.0.0_best_int/spa.traineddata.gz" "$DEST/lang/"
echo "Tesseract listo en $DEST ($(du -sh "$DEST" | cut -f1))"
