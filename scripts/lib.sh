#!/usr/bin/env bash
# Funciones comunes. Los recursos se resuelven por NOMBRE/PREFIJO directamente en AWS,
# de modo que las consultas son independientes de Terraform (verificación independiente).
# Requiere: aws cli v2, jq, curl, date (GNU).

utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
utc_ms() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }

# Enmascara el ID de cuenta (12 dígitos) dejando los 4 últimos.
mask_account() { sed -E 's/([^0-9]|^)[0-9]{8}([0-9]{4})([^0-9]|$)/\1********\2\3/g'; }

asg_name() { printf '%s-asg' "$1"; }

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
