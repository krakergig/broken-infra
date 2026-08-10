# modules/ecs_service/main.tf
# Reusable ECS-on-EC2 service: cluster + EC2 capacity (ASG capacity provider) + ALB
# (HTTPS) + task definition + service + container log group. Used for both the
# application and Jenkins so the two deployments stay consistent (challenge req #3).

# Latest ECS-optimized Amazon Linux 2 AMI, resolved from the public SSM parameter.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# --------------------------------------------------------------------------
# IAM identities the service owns: the EC2 container-host instance role/profile and
# the ECS task execution role. Both are generic (identical for any service), so the
# module creates them. The application/pipeline TASK role is service-specific and is
# passed in by the caller (var.task_role_arn).
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-ecs-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = merge(var.extra_tags, { Name = "${var.name}-ecs-instance" })
}

# Lets the ECS agent register the instance and manage containers.
resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# SSM Session Manager for debugging without opening SSH.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-ecs-instance"
  role = aws_iam_role.instance.name
}

data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
  tags               = merge(var.extra_tags, { Name = "${var.name}-ecs-execution" })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  # Container-host bootstrap script, rendered from a template file. templatefile()
  # injects the cluster name, whether to mount the data volume, and the device name.
  user_data = base64encode(templatefile("${path.module}/scripts/ecs_user_data.sh.tftpl", {
    cluster_name      = aws_ecs_cluster.this.name
    mount_data_volume = var.extra_ebs_volume_size_gb > 0
    device_name       = var.extra_ebs_volume_device_name
  }))
}

# --------------------------------------------------------------------------
# Security groups. These are workload-specific (they encode the ALB->container
# traffic path), so the service owns them rather than the VPC module. Inbound is
# HTTPS-only; outbound is unrestricted (challenge requirement #4).
# --------------------------------------------------------------------------
# ALB SG — public, HTTPS only. (Geo-filtering, where required, is layered on by WAF.)
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "${var.name} ALB: HTTPS from anywhere"
  vpc_id      = var.vpc_id
  tags        = merge(var.extra_tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ECS host SG — reachable only from this service's ALB on the dynamic (bridge) port
# range. Cross-VPC communication goes through the public ALBs, so no peer rule.
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs"
  description = "${var.name} ECS hosts: traffic from its ALB"
  vpc_id      = var.vpc_id
  tags        = merge(var.extra_tags, { Name = "${var.name}-ecs" })
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Dynamic port mapping from this service's ALB"
  ip_protocol                  = "tcp"
  from_port                    = 32768
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --------------------------------------------------------------------------
# ECS cluster.
# --------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = merge(var.extra_tags, { Name = "${var.name}-cluster" })
}

# --------------------------------------------------------------------------
# EC2 capacity: launch template + Auto Scaling Group in the private subnets.
# --------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  vpc_security_group_ids = [aws_security_group.ecs.id]

  # Optional extra EBS data volume (created only when extra_ebs_volume_size_gb > 0).
  # Attached to every container host and mounted at /data by user_data below.
  dynamic "block_device_mappings" {
    for_each = var.extra_ebs_volume_size_gb > 0 ? [1] : []
    content {
      device_name = var.extra_ebs_volume_device_name
      ebs {
        volume_size           = var.extra_ebs_volume_size_gb
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  # Register the instance with this cluster (and mount the data volume if present).
  user_data = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.extra_tags, { Name = "${var.name}-ecs-host" })
  }
}

# ASG spread across the private subnets; provides the cluster's EC2 capacity.
resource "aws_autoscaling_group" "this" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  desired_capacity    = var.instance_count
  min_size            = var.instance_count
  max_size            = var.instance_count + 1

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Required so the ECS capacity provider can manage this ASG.
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Capacity provider ties the ASG to the ECS cluster for EC2 scheduling.
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.this.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }

  tags = merge(var.extra_tags, { Name = "${var.name}-cp" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }
}

# --------------------------------------------------------------------------
# Application Load Balancer (public) with S3 access logging + HTTPS listener.
# --------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # ALB access logs -> shared S3 logging bucket (challenge requirement #6).
  access_logs {
    bucket  = var.log_bucket
    prefix  = "alb/${var.name}"
    enabled = true
  }

  tags = merge(var.extra_tags, { Name = "${var.name}-alb" })
}

# Instance target group with dynamic port mapping (bridge networking).
resource "aws_lb_target_group" "this" {
  name        = substr("${var.name}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.extra_tags, { Name = "${var.name}-tg" })
}

# HTTPS listener (443) — the only inbound path allowed by the SGs/NACLs.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# --------------------------------------------------------------------------
# Container log group + task definition + service.
# --------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
  tags              = merge(var.extra_tags, { Name = "${var.name}-logs" })
}

# --------------------------------------------------------------------------
# Ship container logs to S3 (challenge requirement #6). The awslogs driver above
# streams to CloudWatch (good for live tailing); a subscription filter forwards those
# logs through a Kinesis Firehose delivery stream into the shared S3 log bucket under
# ecs/<name>/, so a durable copy also lives in S3.
# --------------------------------------------------------------------------
locals {
  log_bucket_arn = "arn:aws:s3:::${var.log_bucket}"
}

# Role Firehose assumes to write objects to the log bucket.
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.name}-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
  tags               = merge(var.extra_tags, { Name = "${var.name}-firehose" })
}

data "aws_iam_policy_document" "firehose_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [local.log_bucket_arn, "${local.log_bucket_arn}/ecs/${var.name}/*"]
  }
}

resource "aws_iam_role_policy" "firehose_s3" {
  name   = "${var.name}-firehose-s3"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_s3.json
}

# Firehose delivery stream -> S3 (buffered, gzip-compressed).
resource "aws_kinesis_firehose_delivery_stream" "logs" {
  name        = "${var.name}-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = local.log_bucket_arn
    prefix              = "ecs/${var.name}/"
    error_output_prefix = "ecs/${var.name}/errors/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"
  }

  tags = merge(var.extra_tags, { Name = "${var.name}-logs" })
}

# Role CloudWatch Logs assumes to push log events into Firehose.
data "aws_iam_policy_document" "cwl_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cwl_to_firehose" {
  name               = "${var.name}-cwl-firehose"
  assume_role_policy = data.aws_iam_policy_document.cwl_assume.json
  tags               = merge(var.extra_tags, { Name = "${var.name}-cwl-firehose" })
}

data "aws_iam_policy_document" "cwl_to_firehose" {
  statement {
    effect    = "Allow"
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = [aws_kinesis_firehose_delivery_stream.logs.arn]
  }
}

resource "aws_iam_role_policy" "cwl_to_firehose" {
  name   = "${var.name}-cwl-firehose"
  role   = aws_iam_role.cwl_to_firehose.id
  policy = data.aws_iam_policy_document.cwl_to_firehose.json
}

# Forward all events from the container log group into Firehose (-> S3).
resource "aws_cloudwatch_log_subscription_filter" "to_s3" {
  name            = "${var.name}-to-s3"
  log_group_name  = aws_cloudwatch_log_group.this.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.logs.arn
  role_arn        = aws_iam_role.cwl_to_firehose.arn
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      cpu       = var.cpu
      memory    = var.memory
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0 # dynamic host port -> multiple tasks per instance
          protocol      = "tcp"
        }
      ]
      # Bind-mount the (over-provisioned) host data volume into the container at /data.
      mountPoints = var.extra_ebs_volume_size_gb > 0 ? [
        {
          sourceVolume  = "data"
          containerPath = "/data"
          readOnly      = false
        }
      ] : []
      environment = [for k, v in var.container_environment : { name = k, value = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.name
        }
      }
    }
  ])

  # Host volume backed by the extra EBS data volume mounted at /data (see user_data).
  dynamic "volume" {
    for_each = var.extra_ebs_volume_size_gb > 0 ? [1] : []
    content {
      name      = "data"
      host_path = "/data"
    }
  }

  tags = merge(var.extra_tags, { Name = var.name })
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  # Schedule tasks onto the EC2 capacity provider (no Fargate).
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 0
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 120

  # Let the Jenkins pipeline roll new task-definition revisions without Terraform
  # fighting the deploy.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.https, aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.extra_tags, { Name = var.name })
}
