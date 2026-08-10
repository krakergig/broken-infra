# environments/dev/iam.tf
# ECS *task* roles are service-specific (their policies differ per workload), so they
# are defined here in the composition layer and passed into each ecs_service — this
# keeps them available even if the platform module is swapped out, and keeps the
# generic ecs_service module free of app-specific policy. (The generic execution role
# and instance profile are created inside ecs_service itself.)

data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Application task role — the hello-world container needs no AWS permissions.
resource "aws_iam_role" "app_task" {
  name               = "${local.name_prefix}-app-task"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
  tags               = { Name = "${local.name_prefix}-app-task" }
}

# Jenkins task role — the pipeline needs ECR push/pull, S3 pipeline-log writes, and the
# ability to register task definitions and roll the application ECS service.
resource "aws_iam_role" "jenkins_task" {
  name               = "${local.name_prefix}-jenkins-task"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
  tags               = { Name = "${local.name_prefix}-jenkins-task" }
}

data "aws_iam_policy_document" "jenkins_task" {
  statement {
    sid    = "EcrAccess"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "S3PipelineLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.platform.log_bucket_arn}/pipeline/*"]
  }

  statement {
    sid    = "EcsDeploy"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  # The pipeline registers new app task definitions, so it must be able to pass the
  # app's execution role (created inside module.app_service) and the app task role.
  statement {
    sid       = "PassRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [module.app_service.execution_role_arn, aws_iam_role.app_task.arn]
  }
}

resource "aws_iam_role_policy" "jenkins_task" {
  name   = "${local.name_prefix}-jenkins-task"
  role   = aws_iam_role.jenkins_task.id
  policy = data.aws_iam_policy_document.jenkins_task.json
}
