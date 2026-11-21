#!/usr/bin/env bash
# shellcheck disable=SC2016  # consultas JMESPath con literales `...` intencionales
# Espera el resultado REAL del controlador del cambio (Instance Refresh del ASG) y la
# estabilización: sin refresh activo, destinos healthy >= capacidad deseada, todos los
# destinos registrados healthy y todos usando la versión de Launch Template del ASG.
# El éxito de "terraform apply" no basta: Terraform solo inicia el refresh.
#
# Uso: wait_refresh.sh <prefijo> [epoch_inicio_apply] [timeout_s]
#   ej.: wait_refresh.sh na-u2-c50-a004 "$(date +%s)" 2400
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws jq

PREFIX=${1:?prefijo requerido (ej. na-u2-c50-a004)}
SINCE=${2:-0}
TIMEOUT=${3:-2400}
INTERVAL=15

ASG=$(asg_name "$PREFIX")
TG=$(tg_arn "$PREFIX")
[ "$TG" != "None" ] || { echo "ERROR: no existe el Target Group $PREFIX-tg"; exit 1; }

deadline=$(( $(date +%s) + TIMEOUT ))
echo "[$(utc)] Controlador: Instance Refresh de $ASG | Target Group: $PREFIX-tg"

while :; do
  asg_json=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0]' --output json)
  desired=$(jq -r '.DesiredCapacity' <<<"$asg_json")
  lt_ver=$(jq -r '.LaunchTemplate.Version' <<<"$asg_json")

  ref_json=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" \
    --max-records 1 --query 'InstanceRefreshes[0]' --output json)
  if [ "$ref_json" = "null" ]; then
    rid="-"; status="SinRefresh"; pct="-"; rstart=""
  else
    rid=$(jq -r '.InstanceRefreshId' <<<"$ref_json")
    status=$(jq -r '.Status' <<<"$ref_json")
    pct=$(jq -r '.PercentageComplete // 0' <<<"$ref_json")
    rstart=$(jq -r '.StartTime // ""' <<<"$ref_json")
  fi

  th_json=$(aws elbv2 describe-target-health --target-group-arn "$TG" --output json)
  total=$(jq '.TargetHealthDescriptions | length' <<<"$th_json")
  healthy_ids=$(jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State=="healthy") | .Target.Id] | join(" ")' <<<"$th_json")
  healthy=$(wc -w <<<"$healthy_ids" | tr -d ' ')
  states=$(jq -r '[.TargetHealthDescriptions[] | "\(.Target.Id):\(.TargetHealth.State)"] | join(" ")' <<<"$th_json")

  echo "[$(utc)] refresh=$rid estado=$status avance=${pct}% | LT del ASG=$lt_ver | healthy=$healthy/$desired | destinos: $states"

  case "$status" in
    Pending|InProgress|Cancelling|RollbackInProgress|Baking) running=1 ;;
    *) running=0 ;;
  esac

  if [ "$running" -eq 0 ] && [ "$healthy" -ge "$desired" ] && [ "$total" -eq "$healthy" ]; then
    # shellcheck disable=SC2086
    versions=$(aws autoscaling describe-auto-scaling-instances --instance-ids $healthy_ids \
      --query 'AutoScalingInstances[].LaunchTemplate.Version' --output text | tr '\t' '\n' | sort -u | tr '\n' ' ')
    if [ "$(echo "$versions" | xargs)" = "$lt_ver" ]; then
      echo "[$(utc)] ESTABLE: destinos healthy=$healthy (capacidad deseada $desired) en LT versión $lt_ver"
      break
    fi
    echo "[$(utc)] Destinos con versiones mezcladas: $versions (esperando)"
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "[$(utc)] ERROR: tiempo de espera agotado sin estabilización"
    exit 1
  fi
  sleep "$INTERVAL"
done

# Si este apply inició un refresh, su resultado final debe ser Successful.
if [ -n "${rstart:-}" ] && [ "$(to_epoch "$rstart")" -ge "$SINCE" ]; then
  echo "[$(utc)] Refresh de esta ejecución: $rid | resultado final: $status"
  ref_full=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" \
    --instance-refresh-ids "$rid" --query 'InstanceRefreshes[0].{Inicio:StartTime,Fin:EndTime,Estado:Status,Motivo:StatusReason}' --output json)
  echo "$ref_full"
  [ "$status" = "Successful" ] || { echo "ERROR: el controlador no terminó con éxito"; exit 1; }
else
  echo "[$(utc)] Esta ejecución no inició un Instance Refresh (creación inicial o cambio sin plantilla nueva)."
fi

echo "[$(utc)] Instancias en servicio:"
# shellcheck disable=SC2086
aws ec2 describe-instances --instance-ids $healthy_ids \
  --query 'Reservations[].Instances[].{ID:InstanceId,Zona:Placement.AvailabilityZone,IPPrivada:PrivateIpAddress,Lanzada:LaunchTime,Version:Tags[?Key==`portal_version`]|[0].Value,LT:Tags[?Key==`aws:ec2launchtemplate:version`]|[0].Value}' \
  --output table
