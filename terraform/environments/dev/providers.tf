# environments/dev/providers.tf
# AWS providers for the dev environment. default_tags applies the object-typed `tags`
# variable to every resource (challenge requirement #7). The us_east_1 alias is passed
# to the monitoring module for billing + Route53 health-check metrics.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.tags.environment
      product     = var.tags.product
      service     = var.tags.service
      managed_by  = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      environment = var.tags.environment
      product     = var.tags.product
      service     = var.tags.service
      managed_by  = "terraform"
    }
  }
}
