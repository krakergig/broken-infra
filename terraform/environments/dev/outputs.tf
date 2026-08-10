# environments/dev/outputs.tf

output "app_url" {
  description = "Application URL."
  value       = "https://${module.app_service.alb_dns_name}/"
}

output "jenkins_url" {
  description = "Jenkins URL (geo-restricted)."
  value       = "https://${module.jenkins_service.alb_dns_name}/"
}

output "ecr_repository_url" {
  description = "ECR repository URL for the pipeline to push to."
  value       = module.platform.ecr_repository_url
}

output "log_bucket_name" {
  description = "S3 bucket holding ALB/ECS/pipeline logs."
  value       = module.platform.log_bucket_name
}

output "app_ecs_cluster" {
  description = "App ECS cluster name (for pipeline deploys)."
  value       = module.app_service.cluster_name
}

output "app_ecs_service" {
  description = "App ECS service name (for pipeline deploys)."
  value       = module.app_service.service_name
}

output "sns_topic_arn" {
  description = "Regional SNS topic ARN for alarm notifications."
  value       = module.monitoring.sns_topic_arn
}
