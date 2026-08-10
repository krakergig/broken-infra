# modules/waf/variables.tf
# Reusable regional WAFv2 geo-restriction web ACL: blocks by default, allows only the
# listed countries. Reused by every environment; associate it with an ALB via
# aws_wafv2_web_acl_association in the composition layer.

variable "name" {
  description = "Name for the web ACL."
  type        = string
}

variable "allowed_countries" {
  description = "ISO 3166-1 alpha-2 country codes allowed through."
  type        = list(string)
}
