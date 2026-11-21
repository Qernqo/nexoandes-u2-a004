# Versiones fijadas de Terraform y del provider AWS.
# El backend S3 usa bloqueo nativo (use_lockfile), disponible desde Terraform 1.10
# y estable desde 1.11. La configuración del bucket se entrega en "terraform init"
# (configuración parcial) para no publicar el nombre del bucket ni la cuenta.

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}
