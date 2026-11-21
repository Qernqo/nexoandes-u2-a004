# Orquestación (root) del Portal NexoAndes U2 en AWS.
# Compone dos módulos propios: red (aws_network) y cómputo/entrada (aws_portal).
# Azure queda fuera del alcance práctico de esta entrega (restricción documentada
# en el README y en la bitácora de la Ficha).

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Identidad U2 (convención del curso)
  student     = format("a%03d", var.x)
  name_prefix = "na-u2-${var.course}-${local.student}"

  common_tags = {
    proyecto       = "NexoAndes"
    fase           = "U2"
    alumno         = local.student
    curso          = var.course
    proveedor      = "aws"
    gestionado_por = "terraform"
  }

  # Direccionamiento U2: VPC 10.X.0.0/16, subred A 10.X.10.0/24, subred B 10.X.20.0/24
  vpc_cidr = "10.${var.x}.0.0/16"
  subnets = {
    a = {
      cidr = "10.${var.x}.10.0/24"
      az   = data.aws_availability_zones.available.names[0]
    }
    b = {
      cidr = "10.${var.x}.20.0/24"
      az   = data.aws_availability_zones.available.names[1]
    }
  }

  # Artefacto docente: se integra sin modificar su lógica interna.
  portal_identity = {
    x         = var.x
    student   = local.student
    course    = var.course
    build_ref = var.build_ref
  }

  portal_aws_bootstrap = templatefile(
    "${path.module}/templates/user_data_u2.sh.tpl",
    merge(local.portal_identity, {
      provider       = "aws"
      portal_version = var.app_version
    })
  )
}

module "network" {
  source = "./modules/aws_network"

  name_prefix = local.name_prefix
  vpc_cidr    = local.vpc_cidr
  subnets     = local.subnets
}

module "portal" {
  source = "./modules/aws_portal"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  subnet_ids         = values(module.network.subnet_ids)
  ami_id             = var.ami_id
  instance_type      = var.instance_type
  user_data          = local.portal_aws_bootstrap
  app_version        = var.app_version
  build_ref          = var.build_ref
  base_capacity      = var.base_capacity
  allowed_http_cidrs = var.allowed_http_cidrs
  common_tags        = local.common_tags
}
