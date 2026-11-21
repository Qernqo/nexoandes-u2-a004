#!/usr/bin/env bash
# Genera el ZIP limpio de entrega desde el commit evaluado (solo archivos versionados).
# git archive excluye automáticamente .git/, .terraform/, state y todo lo ignorado.
# Uso: make_zip.sh <APELLIDOS_NOMBRE> [commit=HEAD]   ej.: make_zip.sh PEREZ_SOTO_JUAN
set -euo pipefail
NAME=${1:?APELLIDOS_NOMBRE requerido (ej. PEREZ_SOTO_JUAN)}
REF=${2:-HEAD}
cd "$(git rev-parse --show-toplevel)"

bash scripts/check_repo_hygiene.sh
OUT="EVU2_${NAME}.zip"
git archive --format=zip --prefix="EVU2_${NAME}/" -o "$OUT" "$REF"

echo "Contenido de $OUT:"
unzip -l "$OUT"
# Listado en variable: "unzip | grep -q" con pipefail da falsos negativos (SIGPIPE al cortar grep).
listing=$(unzip -l "$OUT")
if grep -qE '\.tfstate|/\.terraform/|tfplan|\.pem$|\.key$|backend\.hcl$' <<<"$listing"; then
  echo "ERROR: el ZIP contiene archivos prohibidos"; exit 1
fi
grep -q '\.terraform\.lock\.hcl' <<<"$listing" || { echo "ERROR: falta .terraform.lock.hcl"; exit 1; }
echo "ZIP limpio generado: $OUT (commit $(git rev-parse --short "$REF"))"
