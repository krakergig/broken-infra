# modules/monitoring/versions.tf
# Monitoring needs two AWS provider configurations: the regional one (default) and
# us-east-1 (billing + Route53 health-check metrics live only there). The caller must
# pass both via the `providers` argument.

terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.60"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
