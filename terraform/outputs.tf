output "helpdesk_url" {
  description = "Public HTTP URL for the Help Desk application."
  value       = "http://${aws_lb.app.dns_name}"
}
output "ecr_repository_url" {
  description = "ECR repository URL used by Jenkins and EC2 instances."
  value       = aws_ecr_repository.app.repository_url
}
output "autoscaling_group_name" {
  description = "Auto Scaling Group that replaces unhealthy instances."
  value       = aws_autoscaling_group.app.name
}
output "target_group_arn" {
  description = "Target group monitored by the load balancer health check."
  value       = aws_lb_target_group.app.arn
}
