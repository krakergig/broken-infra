# environments/dev/main.tf
# Composition layer for the dev environment. Wires the reusable modules together and
# instantiates the two ECS services directly (there is no "workload" wrapper — grouping
# two service instantiations is exactly what this composition layer is for).
#
# Flow: vpc (x2) + peering + waf + platform -> ecs_service (x2) -> monitoring

# ===========================================================================
# Networking: one reusable VPC module instantiated per VPC, plus peering + WAF.
# ===========================================================================
module "app_vpc" {
  source = "../../modules/vpc"

  name = "${local.name_prefix}-app"
  cidr = var.app_vpc_cidr
}

module "jenkins_vpc" {
  source = "../../modules/vpc"

  name = "${local.name_prefix}-jenkins"
  cidr = var.jenkins_vpc_cidr
}

# Peering between the two VPCs (a two-VPC concern reused by every environment).
module "peering" {
  source = "../../modules/peering"

  name = "${local.name_prefix}-peering"

  requester = {
    vpc_id          = module.app_vpc.vpc_id
    cidr            = module.app_vpc.cidr
    route_table_ids = module.app_vpc.route_table_ids
  }

  accepter = {
    vpc_id          = module.jenkins_vpc.vpc_id
    cidr            = module.jenkins_vpc.cidr
    route_table_ids = module.jenkins_vpc.route_table_ids
  }
}

# Geo-restriction WAF for the Jenkins ALB.
module "jenkins_waf" {
  source = "../../modules/waf"

  name              = "${local.name_prefix}-jenkins-geo"
  allowed_countries = var.jenkins_allowed_countries
}

# Attach the WAF web ACL to the Jenkins ALB (references this env's specific ALB).
resource "aws_wafv2_web_acl_association" "jenkins" {
  resource_arn = module.jenkins_service.alb_arn
  web_acl_arn  = module.jenkins_waf.web_acl_arn
}

# ===========================================================================
# Platform: shared S3 logging, ECR, IAM roles, ALB certificate.
# ===========================================================================
module "platform" {
  source = "../../modules/platform"

  name_prefix = local.name_prefix
  product     = var.tags.product
}

# ===========================================================================
# Workloads: the application and Jenkins, each via the ecs_service module.
# ===========================================================================
# Application service (public-facing hello-world, 2 tasks).
module "app_service" {
  source = "../../modules/ecs_service"

  name   = "${local.name_prefix}-app"
  region = var.region

  vpc_id             = module.app_vpc.vpc_id
  private_subnet_ids = module.app_vpc.private_subnets
  public_subnet_ids  = module.app_vpc.public_subnets

  instance_type  = var.instance_type
  instance_count = var.instances_per_cluster

  image          = var.app_image
  container_port = 8080 # infrastructureascode/hello-world listens on 8080
  desired_count  = 2    # 2 application containers per cluster (challenge #3)

  # FLAW (Terraform): the app is grossly OVER-PROVISIONED on two fronts (the brief's
  # Terraform "over-allocation" flaw), wasting spend without affecting functionality:
  #   1. CPU: the task reserves 2048 CPU units — both vCPUs of a t3.micro (1024 == 1
  #      vCPU) — though the idle-light hello-world container only needs ~256. This pins
  #      one task per instance on CPU alone.
  #   2. Storage: each container host gets a 500 GiB gp3 EBS volume, formatted and
  #      mounted at /data on the host and bind-mounted into the container at /data. It
  #      is a real, usable filesystem — but the workload would realistically use
  #      <10 GiB, so ~490 GiB is permanently paid-for and idle.
  # Memory stays a normal 512 MiB. The task still places and the app still serves —
  # core functionality is intact; only cost/efficiency suffer. Fix: cpu = 256 and
  # extra_ebs_volume_size_gb = 0 (or right-size it to ~10).
  cpu    = 2048
  memory = 512

  extra_ebs_volume_size_gb = 500

  task_role_arn     = aws_iam_role.app_task.arn
  certificate_arn   = module.platform.alb_certificate_arn
  log_bucket        = module.platform.log_bucket_name
  health_check_path = "/"

  extra_tags = { role = "application" }
}

# Jenkins service (CI controller, 1 task, geo-restricted).
module "jenkins_service" {
  source = "../../modules/ecs_service"

  name   = "${local.name_prefix}-jenkins"
  region = var.region

  vpc_id             = module.jenkins_vpc.vpc_id
  private_subnet_ids = module.jenkins_vpc.private_subnets
  public_subnet_ids  = module.jenkins_vpc.public_subnets

  instance_type  = var.instance_type
  instance_count = var.instances_per_cluster

  image          = var.jenkins_image
  container_port = 8080 # Jenkins web UI
  desired_count  = 1    # 1 Jenkins controller per cluster (challenge #3)

  # Correct sizing (contrast with the deliberately over-allocated app task above).
  cpu    = 256
  memory = 512

  task_role_arn     = aws_iam_role.jenkins_task.arn
  certificate_arn   = module.platform.alb_certificate_arn
  log_bucket        = module.platform.log_bucket_name
  health_check_path = "/login" # Jenkins returns 200 on /login when healthy

  extra_tags = { role = "jenkins" }
}

# ===========================================================================
# Monitoring: SNS, Route53 health checks, CloudWatch alarms (needs both providers).
# ===========================================================================
module "monitoring" {
  source = "../../modules/monitoring"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix              = local.name_prefix
  alarm_email              = var.alarm_email
  daily_cost_threshold_usd = var.daily_cost_threshold_usd

  services = {
    app = {
      alb_arn_suffix    = module.app_service.alb_arn_suffix
      alb_dns_name      = module.app_service.alb_dns_name
      cluster_name      = module.app_service.cluster_name
      service_name      = module.app_service.service_name
      health_check_path = "/"
    }
    jenkins = {
      alb_arn_suffix    = module.jenkins_service.alb_arn_suffix
      alb_dns_name      = module.jenkins_service.alb_dns_name
      cluster_name      = module.jenkins_service.cluster_name
      service_name      = module.jenkins_service.service_name
      health_check_path = "/login"
    }
  }
}
