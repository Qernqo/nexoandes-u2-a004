# ---------------------------------------------------------------------------
# Parámetros comunes (identidad U2): se repetirían en cualquier proveedor.
# ---------------------------------------------------------------------------

variable "x" {
  description = "Número asignado por el docente (1 a 254). Define alumno aNNN y el direccionamiento."
  type        = number

  validation {
    condition     = var.x >= 1 && var.x <= 254 && floor(var.x) == var.x
    error_message = "x debe ser un entero entre 1 y 254."
  }
}

variable "course" {
  description = "Código de curso con formato cNN (ej.: c01)."
  type        = string

  validation {
    condition     = can(regex("^c[0-9]{2}$", var.course))
    error_message = "course debe tener el formato cNN (ej.: c01)."
  }
}

variable "build_ref" {
  description = "Referencia real del código desplegado (commit corto). La entrega el pipeline."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{4,80}$", var.build_ref))
    error_message = "build_ref: 4 a 80 caracteres (letras, números, punto, guion o guion bajo)."
  }
}

# ---------------------------------------------------------------------------
# Parámetros específicos de AWS.
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Región AWS autorizada (Learner Lab: us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "app_version" {
  description = "Versión del Portal instalada por el bootstrap en AWS: v1 o v2."
  type        = string

  validation {
    condition     = contains(["v1", "v2"], var.app_version)
    error_message = "app_version debe ser v1 o v2."
  }
}

variable "ami_id" {
  description = "AMI Ubuntu Server LTS fijada (no se usa most_recent para evitar reemplazos no intencionados)."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id debe tener el formato ami-xxxxxxxx."
  }
}

variable "instance_type" {
  description = "Tipo de instancia autorizado en el laboratorio."
  type        = string
  default     = "t3.micro"
}

variable "base_capacity" {
  description = "Capacidad base fija del ASG (destinos saludables mínimos que atienden tráfico)."
  type        = number
  default     = 2

  validation {
    condition     = var.base_capacity >= 2 && var.base_capacity <= 4
    error_message = "base_capacity debe estar entre 2 y 4 (una instancia por zona como mínimo)."
  }
}

variable "allowed_http_cidrs" {
  description = "Orígenes autorizados para HTTP 80 hacia el ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
