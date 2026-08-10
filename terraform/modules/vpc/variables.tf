# modules/vpc/variables.tf
# Deploys ONE VPC (2 public + 2 private subnets) with its public-subnet NACLs.
# Pure network fabric; no workload-specific security groups.

variable "name" {
  description = "Full resource name for this VPC (e.g. cloud-pipeline-develop-app)."
  type        = string
}

variable "cidr" {
  description = "CIDR block for this VPC."
  type        = string
}
