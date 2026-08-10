# modules/platform/main.tf
# Shared platform: S3 log bucket (+policy), ECR repo, IAM roles for ECS, and a
# self-signed ACM certificate for the ALB HTTPS listeners.

# ===========================================================================
# S3 logging bucket (ALB access logs, ECS logs, pipeline logs) — req #6.
# ===========================================================================
resource "random_id" "bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-logs-${random_id.bucket.hex}"
  tags   = { Name = "${var.name_prefix}-logs" }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Expire logs after 30 days to keep storage minimal.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "ALBAccessLogsRegionalAccount"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.logs.arn}/alb/*"]
    actions   = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid       = "ALBAccessLogsServicePrincipal"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.logs.arn}/alb/*"]
    actions   = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "ALBAccessLogsAclCheck"
    effect    = "Allow"
    resources = [aws_s3_bucket.logs.arn]
    actions   = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

# ===========================================================================
# ECR repository for the custom hello-world image (req #1).
# ===========================================================================
resource "aws_ecr_repository" "app" {
  name                 = "${var.name_prefix}-hello-world"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.name_prefix}-hello-world" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ===========================================================================
# Self-signed certificate imported into ACM for ALB HTTPS listeners.
# ===========================================================================
resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "${var.name_prefix}.internal"
    organization = var.product
  }

  validity_period_hours = 8760
  early_renewal_hours   = 720

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem

  tags = { Name = "${var.name_prefix}-alb-cert" }

  lifecycle {
    create_before_destroy = true
  }
}
