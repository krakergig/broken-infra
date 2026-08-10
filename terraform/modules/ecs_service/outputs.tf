# modules/ecs_service/outputs.tf
# Values the root module needs for monitoring (Route53/CloudWatch) and WAF wiring.

output "alb_arn" {
  description = "ARN of the ALB (used for WAF association)."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB (used for Route53 health checks)."
  value       = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch LoadBalancer dimension for 5xx alarms)."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch dimension)."
  value       = aws_lb_target_group.this.arn_suffix
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "execution_role_arn" {
  description = "ECS task execution role ARN created by this module (for pipeline PassRole)."
  value       = aws_iam_role.execution.arn
}
