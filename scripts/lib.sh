#!/usr/bin/env bash
# Funciones comunes. Los recursos se resuelven por NOMBRE/PREFIJO directamente en AWS,
# de modo que las consultas son independientes de Terraform (verificación independiente).
# Requiere: aws cli v2, jq, curl, date (GNU).

utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
utc_ms() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }

# Enmascara el ID de cuenta (12 dígitos) dejando los 4 últimos.
mask_account() { sed -E 's/([^0-9]|^)[0-9]{8}([0-9]{4})([^0-9]|$)/\1********\2\3/g'; }

# Controlador U2 adaptado (la SCP del Learner Lab deniega StartInstanceRefresh): cada versión
# de Launch Template crea un ASG nuevo "<prefijo>-asg-ltN" y Terraform elimina el anterior.
# asg_names: todos los ASG vigentes del prefijo, del más antiguo al más reciente.
asg_names() {
  aws autoscaling describe-auto-scaling-groups \
    --query "sort_by(AutoScalingGroups[?starts_with(AutoScalingGroupName, '$1-asg')], &CreatedTime)[].AutoScalingGroupName" \
    --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d;/^None$/d'
}
# asg_name: el ASG más reciente (el que recibe la versión nueva). Si no hay, el nombre base.
asg_name() {
  local n
  n=$(asg_names "$1" | tail -n 1)
  printf '%s' "${n:-$1-asg}"
}
# Nombres históricos posibles (incluye eliminados) para consultar actividades.
asg_candidates() {
  local i
  printf '%s-asg\n' "$1"
  for i in $(seq 1 12); do printf '%s-asg-lt%s\n' "$1" "$i"; done
}

tg_arn() {
  aws elbv2 describe-target-groups --names "$1-tg" \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "None"
}

alb_dns() {
  aws elbv2 describe-load-balancers --names "$1-alb" \
    --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "None"
}

to_epoch() { date -d "$1" +%s 2>/dev/null || echo 0; }

require_tools() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { echo "ERROR: falta la herramienta '$t'" >&2; exit 2; }
  done
}
