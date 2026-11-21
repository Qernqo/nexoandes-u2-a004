#!/usr/bin/env bash
# Falla si el repositorio versiona state, planes, directorios .terraform, claves o credenciales.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

bad=0
forbidden=$(git ls-files | grep -E '(^|/)\.terraform/|\.tfstate(\.|$)|\.tfstate\.backup$|(^|/)tfplan$|\.tfplan$|(^|/)backend\.hcl$|\.pem$|\.key$|(^|/)\.env$|(^|/)credentials$|id_rsa' || true)
if [ -n "$forbidden" ]; then
  echo "Archivos prohibidos versionados:"; echo "$forbidden"; bad=1
fi

# Patrones de credenciales AWS (access key AKIA/ASIA, secret o session token)
if git grep -nIE '(AKIA|ASIA)[A-Z0-9]{16}|aws_secret_access_key *=|aws_session_token *=' -- . ':!scripts/check_repo_hygiene.sh' >/dev/null 2>&1; then
  echo "Posibles credenciales en archivos versionados:"
  git grep -nIE '(AKIA|ASIA)[A-Z0-9]{16}|aws_secret_access_key *=|aws_session_token *=' -- . ':!scripts/check_repo_hygiene.sh' | cut -c1-120
  bad=1
fi

[ -f terraform/.terraform.lock.hcl ] || { echo "Falta terraform/.terraform.lock.hcl"; bad=1; }

if [ "$bad" -eq 0 ]; then echo "Higiene OK: sin state, planes, claves ni credenciales versionadas."; fi
exit "$bad"
