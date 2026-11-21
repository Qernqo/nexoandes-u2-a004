# Un único contexto AWS (cuenta del Learner Lab, región autorizada).
# No se usan alias: solo hay una configuración del provider.
# Las credenciales NO se escriben aquí: se leen del entorno
# (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN).

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
