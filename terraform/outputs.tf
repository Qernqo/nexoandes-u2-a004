# Salidas por contexto (AWS). Permiten correlacionar código, recursos y endpoint.

output "context" {
  description = "Contexto e identidad U2 desplegados."
  value = {
    proveedor   = "aws"
    region      = var.aws_region
    name_prefix = local.name_prefix
    alumno      = local.student
    curso       = var.course
    x           = var.x
    app_version = var.app_version
    build_ref   = var.build_ref
  }
}

output "network" {
  description = "VPC y subredes reales (CIDR y zona)."
  value = {
    vpc_id   = module.network.vpc_id
    vpc_cidr = module.network.vpc_cidr
    subnets  = module.network.subnets
  }
}

output "portal_endpoint" {
  description = "Endpoint de servicio AWS: DNS del ALB (no la IP de una EC2)."
  value       = "http://${module.portal.alb_dns_name}"
}

output "compute" {
  description = "Controlador y plantilla de cómputo."
  value = {
    asg_name                = module.portal.asg_name
    launch_template_id      = module.portal.launch_template_id
    launch_template_version = module.portal.launch_template_version
    target_group_arn        = module.portal.target_group_arn
    alb_arn                 = module.portal.alb_arn
    base_capacity           = var.base_capacity
    max_capacity            = module.portal.max_capacity
  }
}

output "user_data_bytes" {
  description = "Tamaño del bootstrap renderizado (límite AWS: 16384 bytes antes de base64)."
  value       = length(local.portal_aws_bootstrap)
}
