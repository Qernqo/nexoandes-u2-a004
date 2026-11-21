#!/usr/bin/env bash
# Observación HTTP del endpoint AWS según el protocolo U2:
#   - peticiones PROGRAMADAS cada 2 s (no "2 s después de terminar la anterior"),
#   - timeout 5 s, SIN reintentos (cada fallo queda registrado),
#   - hora UTC programada y real de envío, código HTTP, cuerpo de /api/check.
# Cada petición corre en segundo plano para que un timeout no retrase la siguiente.
#
# Uso: observe_http.sh <endpoint> <etiqueta> [duracion_s=0 (hasta Ctrl+C)] [intervalo_s=2] [timeout_s=5]
#   ej.: observe_http.sh "http://na-u2-c50-a004-alb-123.us-east-1.elb.amazonaws.com" actualizacion_v2
# Detener: Ctrl+C (o crear el archivo indicado como STOP). Inicie >= 60 s antes del cambio
# y deténgalo >= 120 s después de la estabilización (recomendado: 180 s).
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools curl jq date

ENDPOINT=${1:?endpoint requerido}; ENDPOINT=${ENDPOINT%/}
LABEL=${2:?etiqueta requerida (ej. actualizacion_v2)}
DURATION=${3:-0}
INTERVAL=${4:-2}
TIMEOUT=${5:-5}

OUTDIR="$(dirname "$0")/../evidencias"
mkdir -p "$OUTDIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$OUTDIR/${STAMP}_${LABEL}_http.csv"
META="$OUTDIR/${STAMP}_${LABEL}_http.meta"
STOP="$OUTDIR/${STAMP}_${LABEL}.STOP"

echo "seq,programada_utc,enviada_utc,http_code,curl_exit,tiempo_s,version,perfil,passed,alumno,curso,x,proveedor,resource_id,ip_privada,zona,build_ref,sha256_12,observed_at_utc,metadata_age_s,error" > "$OUT"
{
  echo "endpoint=$ENDPOINT/api/check"
  echo "inicio_utc=$(utc)"
  echo "intervalo_programado_s=$INTERVAL"
  echo "timeout_s=$TIMEOUT"
  echo "reintentos=0"
  echo "cliente=$(uname -sr)"
  echo "curl=$(curl --version | head -n1)"
} > "$META"

EMPTY_FIELDS='"","","","","","","","","","","","","",""'

probe() {
  local seq=$1 sched=$2 sent body err meta rc code t fields msg disp
  body=$(mktemp); err=$(mktemp)
  sent=$(utc_ms)
  meta=$(curl -sS --max-time "$TIMEOUT" --retry 0 -H 'Cache-Control: no-cache' \
    -o "$body" -w '%{http_code};%{time_total}' "$ENDPOINT/api/check" 2>"$err")
  rc=$?
  code=${meta%%;*}; t=${meta##*;}
  [ -n "$code" ] || code="000"
  if jq -e 'type == "object"' "$body" >/dev/null 2>&1; then
    disp=$(jq -r '"\(.version) \(.resource_id) \(.private_ip) passed=\(.passed)"' "$body")
    fields=$(jq -r '[.version,.functional_profile,.passed,.student,.course,.x,.provider,.resource_id,.private_ip,.location,.build_ref,(.artifact_sha256 // "" | .[0:12]),.observed_at_utc,.metadata_age_seconds] | map(if . == null then "" else tostring end) | @csv' "$body")
  else
    fields=$EMPTY_FIELDS
    disp="sin JSON"
  fi
  msg=$(head -c 160 "$err" | tr '\n\r",' '    ')
  printf '%s\n' "$seq,$sched,$sent,$code,$rc,$t,$fields,\"$msg\"" >> "$OUT"
  printf '%s  #%-4s HTTP %s  %s\n' "$sent" "$seq" "$code" "$disp"
  rm -f "$body" "$err"
}

running=1
trap 'running=0' INT TERM

echo "Registrando en: $OUT"
echo "Para detener: Ctrl+C  (o: touch $STOP)"
start_ns=$(date +%s%N)
interval_ns=$(( INTERVAL * 1000000000 ))
seq=0
while [ "$running" -eq 1 ] && [ ! -f "$STOP" ]; do
  target=$(( start_ns + seq * interval_ns ))
  if [ "$DURATION" -gt 0 ] && [ $(( (target - start_ns) / 1000000000 )) -ge "$DURATION" ]; then
    break
  fi
  now=$(date +%s%N)
  if [ "$target" -gt "$now" ]; then
    d=$(( target - now ))
    sleep "$(printf '%d.%09d' $(( d / 1000000000 )) $(( d % 1000000000 )))" || true
    [ "$running" -eq 1 ] || break
  fi
  sched=$(date -u -d "@$(( target / 1000000000 )).$(printf '%09d' $(( target % 1000000000 )))" +%Y-%m-%dT%H:%M:%S.%3NZ)
  probe "$seq" "$sched" &
  seq=$(( seq + 1 ))
done

wait
echo "fin_utc=$(utc)" >> "$META"
echo "programadas=$seq" >> "$META"
rm -f "$STOP"
echo "Observación terminada. Peticiones programadas: $seq | Archivo: $OUT"
