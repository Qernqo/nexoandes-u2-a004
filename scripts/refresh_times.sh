#!/usr/bin/env bash
# Muestra los Instance Refresh del ASG con sus horas UTC de inicio y fin.
# "Inicio" del protocolo = StartTime del refresh (instante en que el controlador comienza).
# Uso: refresh_times.sh <prefijo>
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws

PREFIX=${1:?prefijo requerido}
aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$(asg_name "$PREFIX")" --max-records 10 \
  --query 'InstanceRefreshes[].{ID:InstanceRefreshId,Estado:Status,Avance:PercentageComplete,InicioUTC:StartTime,FinUTC:EndTime,Motivo:StatusReason}' \
  --output table
