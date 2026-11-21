variable "name_prefix" {
  description = "Prefijo de nombres na-u2-cNN-aNNN."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (10.X.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR IPv4 válido."
  }
}

variable "subnets" {
  description = "Subredes públicas: clave => { cidr, az }. Deben estar en zonas distintas."
  type = map(object({
    cidr = string
    az   = string
  }))

  validation {
    condition     = length(distinct([for s in values(var.subnets) : s.az])) == length(var.subnets)
    error_message = "Cada subred debe estar en una zona de disponibilidad distinta (requisito del ALB)."
  }
}
