output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "subnet_ids" {
  description = "Mapa clave => ID de subred."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "subnets" {
  description = "Detalle real de cada subred (ID, CIDR, zona)."
  value = {
    for k, s in aws_subnet.public : k => {
      id   = s.id
      cidr = s.cidr_block
      az   = s.availability_zone
    }
  }
}
