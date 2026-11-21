#!/usr/bin/env bash
# Observación del proveedor durante el cambio: capacidad del ASG, salud de destinos del
# Target Group, versión de Launch Template de cada destino y estado del controlador
# (reemplazo de ASG: la SCP del Learner Lab deniega Instance Refresh). Protocolo U2: cada 30 s como máximo (por defecto 20 s).
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
  # Todos los ASG del prefijo: durante el reemplazo conviven el anterior y el nuevo.
  all_json=$(aws autoscaling describe-auto-scaling-groups \
    --query "sort_by(AutoScalingGroups[?starts_with(AutoScalingGroupName, '$PREFIX-asg')], &CreatedTime)" \
    --output json 2>/dev/null || echo '[]')
  th_json=$(aws elbv2 describe-target-health --target-group-arn "$TG" --output json 2>/dev/null || echo '{"TargetHealthDescriptions":[]}')

  # Columnas (compatibles con analyze_window.py):
  #   refresh_id     -> ASG vigentes (unidos por +)
  #   refresh_estado -> Reemplazo (2+ ASG) | Estable (1 ASG) | SinASG
  #   refresh_avance -> instancias InService del ASG más reciente / su capacidad deseada (%)
  #   asg_*          -> suma de capacidades; asg_lt_version = versión del ASG más reciente
  line=$(jq -r --arg now "$now" --argjson all "$all_json" '
    (.TargetHealthDescriptions) as $t
    | ($t | map(select(.TargetHealth.State=="healthy"))) as $h
    | ($all | last // {}) as $new
    | ([$all[] | .Instances[]? | {(.InstanceId): (.LaunchTemplate.Version // "-")}] | add // {}) as $vm
    | ($new.LaunchTemplate.Version // "-") as $lt
    | ([$new.Instances[]? | select(.LifecycleState=="InService")] | length) as $ins
    | [ $now,
        ([$all[].AutoScalingGroupName] | join("+") | if . == "" then "-" else . end),
        (if ($all|length) > 1 then "Reemplazo" elif ($all|length) == 1 then "Estable" else "SinASG" end),
        (if ($new.DesiredCapacity // 0) > 0 then (($ins * 100 / $new.DesiredCapacity)|floor|tostring) else "0" end),
        ([$all[].DesiredCapacity] | add // 0 | tostring), ([$all[].MinSize] | add // 0 | tostring),
        ([$all[].MaxSize] | add // 0 | tostring), $lt,
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
