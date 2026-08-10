# modules/waf/outputs.tf

output "web_acl_arn" {
  description = "ARN of the web ACL (associate with an ALB)."
  value       = aws_wafv2_web_acl.geo.arn
}
