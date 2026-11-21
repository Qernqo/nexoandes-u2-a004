#!/usr/bin/env bash
# shellcheck disable=SC2016  # consultas JMESPath con literales `...` intencionales
# Espera el resultado REAL del controlador del cambio (reemplazo de ASG; la SCP del
# Learner Lab deniega Instance Refresh) y la
# estabilización: un solo ASG vigente, destinos healthy >= capacidad deseada, todos los
# destinos registrados healthy y todos usando la versión de Launch Template del ASG.
# El éxito de "terraform apply" no basta: se comprueban los destinos reales.
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

TG=$(tg_arn "$PREFIX")
[ "$TG" != "None" ] || { echo "ERROR: no existe el Target Group $PREFIX-tg"; exit 1; }

deadline=$(( $(date +%s) + TIMEOUT ))
echo "[$(utc)] Controlador: reemplazo de ASG ($PREFIX-asg-ltN, create_before_destroy) | Target Group: $PREFIX-tg"
echo "[$(utc)] (Adaptación: la SCP del Learner Lab deniega autoscaling:StartInstanceRefresh)"

while :; do
  names=$(asg_names "$PREFIX")
  n_asg=$(printf '%s\n' "$names" | sed '/^$/d' | wc -l | tr -d ' ')
  ASG=$(printf '%s\n' "$names" | tail -n 1)
  asg_json=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0]' --output json)
  desired=$(jq -r '.DesiredCapacity' <<<"$asg_json")
  lt_ver=$(jq -r '.LaunchTemplate.Version' <<<"$asg_json")
  created=$(jq -r '.CreatedTime' <<<"$asg_json")
  if [ "$n_asg" -gt 1 ]; then status="Reemplazo"; else status="Estable"; fi

  th_json=$(aws elbv2 describe-target-health --target-group-arn "$TG" --output json)
  total=$(jq '.TargetHealthDescriptions | length' <<<"$th_json")
  healthy_ids=$(jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State=="healthy") | .Target.Id] | join(" ")' <<<"$th_json")
  healthy=$(wc -w <<<"$healthy_ids" | tr -d ' ')
  states=$(jq -r '[.TargetHealthDescriptions[] | "\(.Target.Id):\(.TargetHealth.State)"] | join(" ")' <<<"$th_json")

  echo "[$(utc)] ASG vigentes=$(printf '%s' "$names" | tr '\n' '+') estado=$status | ASG nuevo=$ASG (LT $lt_ver) | healthy=$healthy/$desired | destinos: $states"

  if [ "$status" = "Estable" ] && [ "$healthy" -ge "$desired" ] && [ "$total" -eq "$healthy" ]; then
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

# Si este apply creó el ASG vigente, se informa como resultado del controlador.
if [ "$(to_epoch "$created")" -ge "$SINCE" ]; then
  echo "[$(utc)] Reemplazo de esta ejecución: ASG $ASG creado $created | resultado final: Successful (ASG anterior eliminado, $healthy healthy en LT $lt_ver)"
else
  echo "[$(utc)] Esta ejecución no creó un ASG nuevo (sin cambio de plantilla)."
fi

echo "[$(utc)] Instancias en servicio:"
# shellcheck disable=SC2086
aws ec2 describe-instances --instance-ids $healthy_ids \
  --query 'Reservations[].Instances[].{ID:InstanceId,Zona:Placement.AvailabilityZone,IPPrivada:PrivateIpAddress,Lanzada:LaunchTime,Version:Tags[?Key==`portal_version`]|[0].Value,LT:Tags[?Key==`aws:ec2launchtemplate:version`]|[0].Value}' \
  --output table
