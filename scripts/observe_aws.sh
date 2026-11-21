#!/usr/bin/env bash
# Observación del proveedor durante el cambio: capacidad del ASG, salud de destinos del
# Target Group, versión de Launch Template de cada destino y estado del controlador
# (Instance Refresh). Protocolo U2: cada 30 s como máximo (por defecto 20 s).
#
# Uso: observe_aws.sh <prefijo> <etiqueta> [intervalo_s=20]
#   ej.: observe_aws.sh na-u2-c50-a004 actualizacion_v2
# Detener con Ctrl+C.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws jq

PREFIX=${1:?prefijo requerido}
LABEL=${2:?etiqueta requerida}
INTERVAL=${3:-20}
[ "$INTERVAL" -le 30 ] || { echo "El protocolo exige <= 30 s"; exit 2; }

ASG=$(asg_name "$PREFIX")
TG=$(tg_arn "$PREFIX")
[ "$TG" != "None" ] || { echo "ERROR: no existe $PREFIX-tg"; exit 1; }

OUTDIR="$(dirname "$0")/../evidencias"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/$(date -u +%Y%m%dT%H%M%SZ)_${LABEL}_aws.csv"
echo "utc,refresh_id,refresh_estado,refresh_avance,asg_deseada,asg_min,asg_max,asg_lt_version,destinos_total,destinos_healthy,healthy_en_lt_asg,detalle" > "$OUT"

running=1
trap 'running=0' INT TERM
echo "Registrando en: $OUT (cada ${INTERVAL}s). Ctrl+C para detener."

while [ "$running" -eq 1 ]; do
  t0=$(date +%s)
  now=$(utc)
  asg_json=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0]' --output json 2>/dev/null || echo '{}')
  ref_json=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 --query 'InstanceRefreshes[0]' --output json 2>/dev/null || echo 'null')
  th_json=$(aws elbv2 describe-target-health --target-group-arn "$TG" --output json 2>/dev/null || echo '{"TargetHealthDescriptions":[]}')

  lt=$(jq -r '.LaunchTemplate.Version // "-"' <<<"$asg_json")
  # Mapa instancia -> versión de Launch Template (desde el ASG)
  ver_map=$(jq -c '[.Instances[]? | {(.InstanceId): (.LaunchTemplate.Version // "-")}] | add // {}' <<<"$asg_json")

  line=$(jq -r --arg now "$now" --arg lt "$lt" --argjson asg "$asg_json" --argjson ref "$ref_json" --argjson vm "$ver_map" '
    (.TargetHealthDescriptions) as $t
    | ($t | map(select(.TargetHealth.State=="healthy"))) as $h
    | [ $now,
        ($ref.InstanceRefreshId // "-"), ($ref.Status // "-"), (($ref.PercentageComplete // 0)|tostring),
        ($asg.DesiredCapacity|tostring), ($asg.MinSize|tostring), ($asg.MaxSize|tostring), $lt,
        ($t|length|tostring), ($h|length|tostring),
        ([$h[] | select(($vm[.Target.Id] // "-") == $lt)] | length | tostring),
        ([$t[] | "\(.Target.Id):lt\($vm[.Target.Id] // "-"):\(.TargetHealth.State)"] | join(" "))
      ] | @csv' <<<"$th_json")
  echo "$line" >> "$OUT"
  echo "$line"

  # Esperar hasta completar el intervalo (sin acumular deriva)
  while [ "$running" -eq 1 ] && [ $(( $(date +%s) - t0 )) -lt "$INTERVAL" ]; do sleep 1; done
done
echo "Observación del proveedor terminada: $OUT"
