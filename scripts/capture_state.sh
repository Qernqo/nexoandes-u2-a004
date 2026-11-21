#!/usr/bin/env bash
# shellcheck disable=SC2016  # consultas JMESPath con literales `...` intencionales
# Consulta INDEPENDIENTE al proveedor (AWS CLI, sin Terraform) + muestras HTTP.
# Genera un registro con hora UTC para E03, E05, E07 y E08 (antes de limpiar).
# Uso: capture_state.sh <prefijo> <etiqueta>
#   ej.: capture_state.sh na-u2-c50-a004 E03_v1_inicial
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws jq curl

PREFIX=${1:?prefijo requerido}
LABEL=${2:?etiqueta requerida}
OUTDIR="$(dirname "$0")/../evidencias"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/$(date -u +%Y%m%dT%H%M%SZ)_${LABEL}_estado.txt"
ASG=$(asg_name "$PREFIX")

section() { printf '\n===== %s =====\n' "$1"; }

{
  echo "Registro: $LABEL | prefijo: $PREFIX | generado: $(utc)"
  section "Contexto (cuenta enmascarada)"
  aws sts get-caller-identity --query '{Cuenta:Account,Arn:Arn}' --output table
  echo "Región: ${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region)}}"

  section "VPC y subredes"
  VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$PREFIX-aws-vpc" --query 'Vpcs[0].VpcId' --output text)
  aws ec2 describe-vpcs --vpc-ids "$VPC" \
    --query 'Vpcs[].{VPC:VpcId,CIDR:CidrBlock,Alumno:Tags[?Key==`alumno`]|[0].Value,Curso:Tags[?Key==`curso`]|[0].Value,Fase:Tags[?Key==`fase`]|[0].Value,Proveedor:Tags[?Key==`proveedor`]|[0].Value}' --output table
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
    --query 'Subnets[].{Subred:SubnetId,Nombre:Tags[?Key==`Name`]|[0].Value,CIDR:CidrBlock,Zona:AvailabilityZone,IPPublicaAuto:MapPublicIpOnLaunch}' --output table
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
    --query 'RouteTables[].Routes[].{Destino:DestinationCidrBlock,Gateway:GatewayId,Estado:State}' --output table

  section "Entrada de tráfico: ALB / listener / Target Group"
  aws elbv2 describe-load-balancers --names "$PREFIX-alb" \
    --query 'LoadBalancers[].{Nombre:LoadBalancerName,DNS:DNSName,Esquema:Scheme,Estado:State.Code,Zonas:join(`,`,AvailabilityZones[].ZoneName)}' --output table
  TG=$(tg_arn "$PREFIX")
  aws elbv2 describe-target-groups --target-group-arns "$TG" \
    --query 'TargetGroups[].{TG:TargetGroupName,Puerto:Port,HealthPath:HealthCheckPath,Intervalo:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount}' --output table
  aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query 'TargetHealthDescriptions[].{Instancia:Target.Id,Puerto:Target.Port,Estado:TargetHealth.State,Motivo:TargetHealth.Reason}' --output table

  section "Controlador: Auto Scaling Group"
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[].{ASG:AutoScalingGroupName,Min:MinSize,Deseada:DesiredCapacity,Max:MaxSize,LT:LaunchTemplate.LaunchTemplateName,LTVersion:LaunchTemplate.Version,HealthCheck:HealthCheckType}' --output table
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].Instances[].{Instancia:InstanceId,Zona:AvailabilityZone,Ciclo:LifecycleState,Salud:HealthStatus,LTVersion:LaunchTemplate.Version}' --output table

  section "Instancias EC2 del Portal (incluye terminadas recientes)"
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$PREFIX-ec2" \
    --query 'Reservations[].Instances[].{ID:InstanceId,Estado:State.Name,Zona:Placement.AvailabilityZone,IPPrivada:PrivateIpAddress,IPPublica:PublicIpAddress,Lanzada:LaunchTime,Version:Tags[?Key==`portal_version`]|[0].Value,Build:Tags[?Key==`build_ref`]|[0].Value,LT:Tags[?Key==`aws:ec2launchtemplate:version`]|[0].Value}' --output table

  section "Plantilla de cómputo: versiones de Launch Template"
  aws ec2 describe-launch-template-versions --launch-template-name "$PREFIX-lt" \
    --query 'LaunchTemplateVersions[].{Version:VersionNumber,Default:DefaultVersion,Creada:CreateTime,Descripcion:VersionDescription,AMI:LaunchTemplateData.ImageId,Tipo:LaunchTemplateData.InstanceType}' --output table

  section "Instance Refresh (últimos 5)"
  aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 5 \
    --query 'InstanceRefreshes[].{ID:InstanceRefreshId,Estado:Status,Avance:PercentageComplete,Inicio:StartTime,Fin:EndTime,MinHealthy:Preferences.MinHealthyPercentage,MaxHealthy:Preferences.MaxHealthyPercentage}' --output table

  section "Actividades de escalado (últimas 10: distingue reemplazos automáticos)"
  aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-items 10 \
    --query 'Activities[].{Inicio:StartTime,Estado:StatusCode,Descripcion:Description,Causa:Cause}' --output table

  section "Prueba HTTP por el endpoint de servicio"
  DNS=$(alb_dns "$PREFIX")
  echo "Endpoint: http://$DNS"
  for _ in 1 2 3 4 5 6; do
    curl -sS --max-time 5 -w '  <- HTTP %{http_code}\n' "http://$DNS/api/check" \
      | jq -c '{observed_at_utc,version,functional_profile,passed,student,course,x,provider,build_ref,resource_id,private_ip,location,hostname,artifact_sha256,metadata_age_seconds}' 2>/dev/null \
      || echo "  (sin respuesta JSON)"
    sleep 2
  done
} 2>&1 | mask_account | tee "$OUT"

echo
echo "Registro guardado en: $OUT"
