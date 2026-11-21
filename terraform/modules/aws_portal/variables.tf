variable "name_prefix" {
  description = "Prefijo de nombres na-u2-cNN-aNNN."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se despliega el Portal."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes públicas en zonas distintas (ALB y ASG)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Se requieren al menos dos subredes en zonas distintas."
  }
}

variable "ami_id" {
  description = "AMI fijada para la plantilla de cómputo."
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia."
  type        = string
}

variable "user_data" {
  description = "Bootstrap renderizado (sin codificar). El módulo lo codifica en base64."
  type        = string

  validation {
    condition     = length(var.user_data) <= 16384
    error_message = "El bootstrap renderizado supera el límite de 16 KiB de user data."
  }
}

variable "app_version" {
  description = "Versión del Portal (v1/v2): se refleja en tags y descripción de la plantilla."
  type        = string
}

variable "build_ref" {
  description = "Referencia del commit desplegado."
  type        = string
}

variable "base_capacity" {
  description = "Capacidad base fija."
  type        = number
}

variable "allowed_http_cidrs" {
  description = "Orígenes autorizados hacia el ALB."
  type        = list(string)
}

variable "common_tags" {
  description = "Tags comunes U2 (se aplican a instancias, volúmenes, ENI y ASG)."
  type        = map(string)
}
