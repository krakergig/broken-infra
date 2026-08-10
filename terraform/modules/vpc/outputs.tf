# modules/vpc/outputs.tf

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "cidr" {
  description = "VPC CIDR block."
  value       = var.cidr
}

output "private_subnets" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "route_table_ids" {
  description = "All route table IDs (private + public) — used to add peering routes."
  value       = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
}
