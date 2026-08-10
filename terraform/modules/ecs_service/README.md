# `ecs_service` module

Reusable module that deploys a single containerized service on **ECS-on-EC2** behind
a public **HTTPS Application Load Balancer**. Used for both the hello-world
application and the Jenkins controller so the two deployments stay consistent.

## What it creates
- ECS cluster (Container Insights enabled)
- **EC2 instance role + instance profile** and the **ECS task execution role** (generic
  identities the module owns; the app-specific **task role** is passed in)
- **ALB + ECS-host security groups** (HTTPS-only inbound; optional peered-VPC ingress)
- Launch template + Auto Scaling Group of `t3.micro` container hosts in **private** subnets
  (optionally with an extra EBS data volume via `extra_ebs_volume_size_gb`)
- ECS capacity provider bound to the ASG (no Fargate)
- Application Load Balancer in **public** subnets with S3 access logging
- HTTPS (443) listener using the supplied ACM certificate
- Instance target group with dynamic port mapping (bridge networking)
- CloudWatch log group + **Firehose export of container logs to S3** (`ecs/<name>/`)
- ECS task definition + ECS service

## Usage
```hcl
module "app_service" {
  source = "./modules/ecs_service"

  name               = "cloud-pipeline-dev-app"
  region             = "eu-central-1"
  vpc_id             = module.app_vpc.vpc_id
  private_subnet_ids = module.app_vpc.private_subnets
  public_subnet_ids  = module.app_vpc.public_subnets
  image              = "infrastructureascode/hello-world:latest"
  container_port     = 8080
  desired_count      = 2
  cpu                = 256
  memory             = 512
  task_role_arn      = aws_iam_role.app_task.arn   # app-specific, supplied by caller
  certificate_arn    = aws_acm_certificate.alb.arn
  log_bucket         = aws_s3_bucket.logs.bucket
  health_check_path  = "/"
}
```

## Key inputs
| Name | Description | Default |
|------|-------------|---------|
| `name` | Resource name prefix | — |
| `image` | Container image | — |
| `container_port` | Container listen port | — |
| `desired_count` | Number of task copies | `1` |
| `cpu` / `memory` | Task size (units / MiB) | `256` / `512` |
| `instance_count` | EC2 hosts in the ASG | `2` |
| `health_check_path` | ALB health-check path | `/` |

## Outputs
`alb_arn`, `alb_dns_name`, `alb_arn_suffix`, `target_group_arn_suffix`,
`cluster_name`, `service_name`.

> Note: the **Terraform flaw** (CPU over-allocation) lives in the composition layer's
> `ecs_service` call (`environments/dev/main.tf`), not in this module itself — this
> module faithfully applies whatever `cpu` value it is given.
