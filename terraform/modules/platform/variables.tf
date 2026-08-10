# modules/platform/variables.tf
# Inputs for the shared platform layer: log bucket, ECR, IAM roles, ALB certificate.

variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "product" {
  description = "Product tag value, used as the certificate organization."
  type        = string
}
