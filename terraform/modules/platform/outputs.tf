# modules/platform/outputs.tf

output "log_bucket_name" {
  description = "Name of the shared S3 logging bucket."
  value       = aws_s3_bucket.logs.bucket
}

output "log_bucket_arn" {
  description = "ARN of the shared S3 logging bucket."
  value       = aws_s3_bucket.logs.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the app image."
  value       = aws_ecr_repository.app.repository_url
}

output "alb_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS listeners."
  value       = aws_acm_certificate.alb.arn
}
