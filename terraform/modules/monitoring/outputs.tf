# modules/monitoring/outputs.tf

output "sns_topic_arn" {
  description = "Regional SNS topic ARN for alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_arn_us_east_1" {
  description = "us-east-1 SNS topic ARN (billing + health-check alarms)."
  value       = aws_sns_topic.alarms_use1.arn
}
