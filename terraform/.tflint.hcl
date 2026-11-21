# Reglas recomendadas de Terraform (nombres, variables sin uso, versiones declaradas).
# Opcional: agregar el plugin tflint-ruleset-aws fijando una versión publicada.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
