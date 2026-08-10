# environments/dev/locals.tf

locals {
  # Naming convention: <product>-<service>-<environment>, e.g. cloud-pipeline-develop.
  name_prefix = "${var.tags.product}-${var.tags.service}-${var.tags.environment}"
}
