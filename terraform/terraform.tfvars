# Parámetros NO secretos del despliegue U2 (se versionan).
# build_ref NO va aquí: lo calcula el pipeline a partir del commit.

# --- Identidad (reemplazar por los valores asignados por el docente) ---
x      = 4
course = "c50"

# --- AWS ---
aws_region    = "us-east-1"
instance_type = "t3.micro"
base_capacity = 2

# AMI Ubuntu Server 24.04 LTS (amd64) fijada. Obtener el ID real con el comando
# indicado en la guía (Fase 3) y reemplazar el valor de ejemplo.
ami_id = "ami-0a951420c495183dc"

# Versión del Portal que debe atender tráfico: v1 -> v2 -> v1 (recuperación)
app_version = "v1"
