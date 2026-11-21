#!/usr/bin/env bash
# Horas UTC del controlador del cambio.
# ADAPTACIÓN U2: la SCP del Learner Lab deniega autoscaling:StartInstanceRefresh, por lo que
# el cambio se ejecuta como REEMPLAZO DE ASG (<prefijo>-asg-ltN, create_before_destroy).
#   InicioUTC = primera actividad "Launching" del ASG nuevo (el controlador comienza).
#   FinUTC    = última actividad "Terminating" del ASG anterior (EndTime): el anterior quedó vacío.
# Se consultan también ASG ya eliminados (--include-deleted-groups).
# Uso: refresh_times.sh <prefijo>
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws jq

PREFIX=${1:?prefijo requerido}

printf '%-26s %-9s %-22s %-22s %-22s %-22s %s\n' "ASG" "Vigente" "PrimerLanzamientoUTC" "UltimoLanzamientoFin" "PrimeraTerminacion" "UltimaTerminacionFin" "Lanz/Term"
current=$(asg_names "$PREFIX" | tr '\n' ' ')
while read -r name; do
  act=$(aws autoscaling describe-scaling-activities --auto-scaling-group-name "$name" \
    --include-deleted-groups --max-items 100 --output json 2>/dev/null || echo '{"Activities":[]}')
  [ "$(jq '.Activities | length' <<<"$act")" -gt 0 ] || continue
  jq -r --arg n "$name" --arg vig "$(grep -qw -- "$name" <<<"$current" && echo si || echo no)" '
    (.Activities | map(select(.Description|test("^Launching")))) as $l
    | (.Activities | map(select(.Description|test("^Terminating")))) as $t
    | [ $n, $vig,
        ($l | map(.StartTime) | min // "-"), ($l | map(.EndTime // "-") | max // "-"),
        ($t | map(.StartTime) | min // "-"), ($t | map(.EndTime // "-") | max // "-"),
        "\($l|length)/\($t|length)" ] | @tsv' <<<"$act" \
    | awk -F'\t' 'function z(v) { return v == "-" ? "-" : substr(v, 1, 19) "Z" }
                   { printf "%-26s %-9s %-22s %-22s %-22s %-22s %s\n", $1, $2, z($3), z($4), z($5), z($6), $7 }'
done < <(asg_candidates "$PREFIX")

echo
echo "Para analyze_window.py: --start = PrimerLanzamientoUTC del ASG nuevo;"
echo "--stable = la más tardía entre UltimaTerminacionFin del ASG anterior y la línea ESTABLE de wait_refresh.log."
