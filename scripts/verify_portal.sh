#!/usr/bin/env bash
# Verificación HTTP/funcional del Portal por su endpoint de servicio (DNS del ALB).
# Comprueba código HTTP, cuerpo (passed), versión e identidad U2 en cada respuesta.
# Uso: verify_portal.sh <endpoint> <version> <alumno> <curso> <x> [muestras]
#   ej.: verify_portal.sh http://na-u2-...elb.amazonaws.com v1 a004 c50 4 15
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools curl jq

ENDPOINT=${1:?endpoint requerido}; ENDPOINT=${ENDPOINT%/}
VERSION=${2:?versión esperada (v1|v2)}
STUDENT=${3:?alumno aNNN}; COURSE=${4:?curso cNN}; X=${5:?X}
N=${6:-15}

# Un ALB recién creado puede tardar en resolver por DNS: esperar hasta 5 min.
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$ENDPOINT/health" || true)
  [ "$code" = "200" ] && break
  sleep 5
done

fails=0
printf '%-24s %-4s %-3s %-9s %-20s %-15s %-11s %s\n' UTC HTTP VER PERFIL ID IP_PRIVADA ZONA SHA256
for i in $(seq 1 "$N"); do
  body=$(mktemp)
  code=$(curl -sS --max-time 5 -o "$body" -w '%{http_code}' "$ENDPOINT/api/check" 2>/dev/null) || code="000"
  if jq -e . "$body" >/dev/null 2>&1; then
    read -r ver prof passed stu cou xx prov rid ip loc sha < <(jq -r \
      '[.version,.functional_profile,.passed,.student,.course,.x,.provider,.resource_id,.private_ip,.location,(.artifact_sha256 // "" | .[0:12])] | map(if . == null or . == "" then "-" else tostring end) | @tsv' "$body")
  else
    ver="-"; prof="-"; passed="false"; stu="-"; cou="-"; xx="-"; prov="-"; rid="-"; ip="-"; loc="-"; sha="-"
  fi
  rm -f "$body"
  printf '%-24s %-4s %-3s %-9s %-20s %-15s %-11s %s\n' "$(utc)" "$code" "$ver" "$prof" "$rid" "$ip" "$loc" "$sha"
  if [ "$code" != "200" ] || [ "$passed" != "true" ] || [ "$ver" != "$VERSION" ] || \
     [ "$stu" != "$STUDENT" ] || [ "$cou" != "$COURSE" ] || [ "$xx" != "$X" ] || [ "$prov" != "aws" ]; then
    fails=$((fails + 1))
    echo "  -> FALLO en la muestra $i"
  fi
  [ "$i" -lt "$N" ] && sleep 2
done

echo "Muestras: $N | fallos: $fails | versión esperada: $VERSION | identidad: $STUDENT/$COURSE/X=$X"
[ "$fails" -eq 0 ]
