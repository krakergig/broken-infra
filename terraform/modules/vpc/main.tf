# modules/vpc/main.tf
# One VPC with 2 public + 2 private subnets and public-subnet NACLs (HTTPS-only
# inbound). Pure network fabric — workload-specific security groups live with the
# service that uses them (see modules/ecs_service).

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  private_subnets = [cidrsubnet(var.cidr, 8, 1), cidrsubnet(var.cidr, 8, 2)]
  public_subnets  = [cidrsubnet(var.cidr, 8, 101), cidrsubnet(var.cidr, 8, 102)]
}

# ---------------------------------------------------------------------------
# VPC (challenge requirement #2) — community module, one instance per VPC.
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = var.name
  cidr = var.cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT per VPC to minimise cost
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = var.name }
}

# ---------------------------------------------------------------------------
# Public-subnet NACL — block non-HTTPS inbound (challenge requirement #4).
# Stateless, so an ephemeral inbound rule admits return traffic.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
  tags       = { Name = "${var.name}-public-nacl" }
}

resource "aws_network_acl_rule" "in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}
