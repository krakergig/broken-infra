# modules/waf/main.tf
# Regional WAFv2 web ACL enforcing a geo allow-list (challenge requirement #4).

resource "aws_wafv2_web_acl" "geo" {
  name        = var.name
  description = "Allow access only from approved countries"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "allow-approved-countries"
    priority = 1

    action {
      allow {}
    }

    statement {
      geo_match_statement {
        country_codes = var.allowed_countries
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-allow"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = var.name }
}
