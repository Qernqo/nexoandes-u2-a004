# Módulo aws_portal: entrada de tráfico (ALB + Target Group) y cómputo inmutable
# (Launch Template versionada + Auto Scaling Group con Instance Refresh rolling).
#
# Controlador único del cambio: Instance Refresh del ASG. Terraform lo inicia cuando
# cambia la versión de la Launch Template; el pipeline espera su resultado final.

locals {
  # Capacidad temporal: hasta base_capacity instancias extra durante el reemplazo
  # (launch before terminate: min_healthy 100 %, max_healthy 200 %).
  max_capacity = var.base_capacity * 2

  instance_tags = merge(var.common_tags, {
    Name           = "${var.name_prefix}-ec2"
    portal_version = var.app_version
    build_ref      = var.build_ref
  })
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-sg-alb"
  description = "ALB del Portal: HTTP 80 desde origenes autorizados"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg-alb"
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-sg-ec2"
  description = "EC2 del Portal: HTTP 80 solo desde el SG del ALB; sin SSH"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-sg-ec2"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP 80 hacia el ALB"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB hacia destinos (puerto de aplicacion y health check)"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "HTTP 80 unicamente desde el SG del ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

# Salida autorizada para el bootstrap (repositorios del sistema si faltara python3).
resource "aws_vpc_security_group_egress_rule" "ec2_out" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.ec2.id
  description       = "Salida ${each.value}/tcp para bootstrap y dependencias del sistema"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Entrada de tráfico: ALB internet-facing, Target Group y listener HTTP 80
# ---------------------------------------------------------------------------

resource "aws_lb" "portal" {
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "portal" {
  name                 = "${var.name_prefix}-tg"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  # /api/check devuelve 200 solo si la comprobación funcional pasa (503 si no).
  health_check {
    enabled             = true
    path                = "/api/check"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.name_prefix}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.portal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }

  tags = {
    Name = "${var.name_prefix}-listener-http"
  }
}

# ---------------------------------------------------------------------------
# Plantilla de cómputo versionada (imagen fijada + bootstrap + versión del Portal)
# ---------------------------------------------------------------------------

resource "aws_launch_template" "portal" {
  name                   = "${var.name_prefix}-lt"
  description            = "Portal NexoAndes U2 ${var.app_version} build ${var.build_ref}"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  update_default_version = true

  # El artefacto docente se entrega como user_data en base64 (límite 16 KiB).
  user_data = base64encode(var.user_data)

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.ec2.id]
  }

  # IMDSv2 obligatorio (el Portal usa exclusivamente IMDSv2).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.instance_tags
  }

  tags = {
    Name           = "${var.name_prefix}-lt"
    portal_version = var.app_version
    build_ref      = var.build_ref
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group: capacidad base fija + Instance Refresh rolling
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "portal" {
  # ADAPTACIÓN (restricción del Learner Lab): la SCP de la cuenta deniega
  # autoscaling:StartInstanceRefresh. El controlador del cambio pasa a ser el
  # REEMPLAZO DEL ASG: el nombre incluye la versión de la Launch Template, de modo
  # que una versión nueva crea un ASG nuevo (create_before_destroy) en el MISMO
  # Target Group; Terraform espera sus destinos healthy y solo entonces elimina el
  # ASG anterior. Si el nuevo no alcanza la capacidad, el apply falla y el ASG
  # anterior sigue atendiendo (detención automática).
  name                = "${var.name_prefix}-asg-lt${aws_launch_template.portal.latest_version}"
  min_size            = var.base_capacity
  desired_capacity    = var.base_capacity
  max_size            = local.max_capacity
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.portal.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 180

  # En la creación de cada ASG (cada versión): esperar destinos healthy en el ALB
  # antes de continuar (y, por create_before_destroy, antes de eliminar el anterior).
  min_elb_capacity          = var.base_capacity
  wait_for_capacity_timeout = "15m"

  # Versión explícita: cada cambio de plantilla es una versión nueva => ASG nuevo.
  launch_template {
    id      = aws_launch_template.portal.id
    version = aws_launch_template.portal.latest_version
  }

  lifecycle {
    create_before_destroy = true
  }

  dynamic "tag" {
    for_each = merge(var.common_tags, { Name = "${var.name_prefix}-asg" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false # las instancias se etiquetan desde la Launch Template
    }
  }
}
