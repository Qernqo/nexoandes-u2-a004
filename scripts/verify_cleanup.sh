#!/usr/bin/env bash
# Comprobación INDEPENDIENTE de limpieza en AWS (E08), por categoría de recurso.
# Uso: verify_cleanup.sh <prefijo>      ej.: verify_cleanup.sh na-u2-c50-a004
# Devuelve 0 si no queda ningún recurso evaluado; 1 si alguno sigue presente.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require_tools aws

PREFIX=${1:?prefijo requerido}
STUDENT=$(echo "$PREFIX" | awk -F- '{print $4}')
present=0

check() {
  local label=$1 value=$2
  if [ -z "$value" ] || [ "$value" = "None" ] || [ "$value" = "0" ]; then
    printf '%-38s ELIMINADO\n' "$label"
  else
    printf '%-38s PRESENTE -> %s\n' "$label" "$value"
    present=1
  fi
}

echo "Comprobación de limpieza AWS | prefijo $PREFIX | $(utc)"
check "EC2 no terminadas ($PREFIX-ec2)" "$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$PREFIX-ec2" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
check "Auto Scaling Group" "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$(asg_name "$PREFIX")" \
  --query 'AutoScalingGroups[].AutoScalingGroupName' --output text)"
check "Launch Template" "$(aws ec2 describe-launch-templates --filters "Name=launch-template-name,Values=$PREFIX-lt" \
  --query 'LaunchTemplates[].LaunchTemplateId' --output text)"
check "Application Load Balancer" "$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='$PREFIX-alb'].LoadBalancerName" --output text)"
check "Target Group" "$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?TargetGroupName=='$PREFIX-tg'].TargetGroupName" --output text)"
check "Security Groups" "$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$PREFIX-sg-*" \
  --query 'SecurityGroups[].GroupId' --output text)"
check "Subredes" "$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$PREFIX-subnet-*" \
  --query 'Subnets[].SubnetId' --output text)"
check "Internet Gateway" "$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$PREFIX-igw" \
  --query 'InternetGateways[].InternetGatewayId' --output text)"
check "VPC" "$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$PREFIX-aws-vpc" \
  --query 'Vpcs[].VpcId' --output text)"
check "Volúmenes EBS del Portal" "$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=$PREFIX-ec2" \
  --query 'Volumes[].VolumeId' --output text)"
check "ENI del Portal" "$(aws ec2 describe-network-interfaces --filters "Name=tag:Name,Values=$PREFIX-ec2" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)"

echo
echo "Consulta complementaria por tags (alumno=$STUDENT, fase=U2). La API de etiquetas puede"
echo "mostrar por unos minutos recursos ya eliminados; prevalecen las consultas anteriores."
aws resourcegroupstaggingapi get-resources --tag-filters "Key=alumno,Values=$STUDENT" "Key=fase,Values=U2" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text 2>&1 | mask_account || true

echo
if [ "$present" -eq 0 ]; then
  echo "RESULTADO: sin recursos evaluados presentes ($(utc))"
else
  echo "RESULTADO: quedan recursos presentes ($(utc)) — revisar antes de afirmar limpieza"
fi
exit "$present"
