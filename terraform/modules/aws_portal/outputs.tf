output "alb_dns_name" {
  value = aws_lb.portal.dns_name
}

output "alb_arn" {
  value = aws_lb.portal.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.portal.arn
}

output "asg_name" {
  value = aws_autoscaling_group.portal.name
}

output "launch_template_id" {
  value = aws_launch_template.portal.id
}

output "launch_template_version" {
  value = aws_launch_template.portal.latest_version
}

output "max_capacity" {
  value = local.max_capacity
}
