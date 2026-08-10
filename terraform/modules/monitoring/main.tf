# modules/monitoring/main.tf
# Monitoring: SNS topics (regional + us-east-1), and — per monitored service — a
# Route53 health check plus CloudWatch alarms for 5xx, 4xx, CPU and memory. A single
# account-wide estimated-charges (cost) alarm is also created.

# ===========================================================================
# SNS topics + email subscriptions (req #3 / #5).
# ===========================================================================
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
  tags = { Name = "${var.name_prefix}-alarms" }
}

data "aws_iam_policy_document" "sns_alarms" {
  statement {
    sid       = "AllowCloudWatchPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.sns_alarms.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# us-east-1 topic for the billing + health-check alarms (must be same-region).
resource "aws_sns_topic" "alarms_use1" {
  provider = aws.us_east_1
  name     = "${var.name_prefix}-alarms-use1"
  tags     = { Name = "${var.name_prefix}-alarms-use1" }
}

data "aws_iam_policy_document" "sns_alarms_use1" {
  statement {
    sid       = "AllowCloudWatchPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms_use1.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms_use1" {
  provider = aws.us_east_1
  arn      = aws_sns_topic.alarms_use1.arn
  policy   = data.aws_iam_policy_document.sns_alarms_use1.json
}

resource "aws_sns_topic_subscription" "email_use1" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alarms_use1.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ===========================================================================
# Per-service Route53 health checks (req #3) — one per entry in var.services.
# ===========================================================================
resource "aws_route53_health_check" "this" {
  for_each = var.services

  fqdn              = each.value.alb_dns_name
  type              = "HTTPS"
  port              = 443
  resource_path     = each.value.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.name_prefix}-${each.key}-hc" }
}

# ===========================================================================
# Per-service CloudWatch alarms (req #3 / #5).
# ===========================================================================
# ALB 5xx — server errors: fire on any occurrence (regional).
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-5xx"
  alarm_description   = "${each.key} ALB returned one or more 5xx (server) responses."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = { Name = "${var.name_prefix}-${each.key}-5xx" }
}

# ALB 4xx — client errors: expected in small volumes, so alarm on a SPIKE over 5 min
# rather than on any single occurrence (regional).
resource "aws_cloudwatch_metric_alarm" "http_4xx" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-4xx"
  alarm_description   = "${each.key} app returned an elevated number of 4xx (client) responses."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_4XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.target_4xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = { Name = "${var.name_prefix}-${each.key}-4xx" }
}

# ECS service CPU utilization (regional).
resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-cpu-high"
  alarm_description   = "${each.key} ECS service CPU utilization is high."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = each.value.cluster_name
    ServiceName = each.value.service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = { Name = "${var.name_prefix}-${each.key}-cpu-high" }
}

# ECS service memory utilization (regional).
resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-memory-high"
  alarm_description   = "${each.key} ECS service memory utilization is high."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.memory_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = each.value.cluster_name
    ServiceName = each.value.service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = { Name = "${var.name_prefix}-${each.key}-memory-high" }
}

# Route53 health-check status (metric only exists in us-east-1).
resource "aws_cloudwatch_metric_alarm" "healthcheck" {
  for_each = var.services
  provider = aws.us_east_1

  alarm_name          = "${var.name_prefix}-${each.key}-healthcheck"
  alarm_description   = "${each.key} ALB Route53 health check is failing."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.this[each.key].id
  }

  alarm_actions = [aws_sns_topic.alarms_use1.arn]
  ok_actions    = [aws_sns_topic.alarms_use1.arn]
  tags          = { Name = "${var.name_prefix}-${each.key}-healthcheck" }
}

# ===========================================================================
# Daily cost alarm (billing metric lives in us-east-1).
# EstimatedCharges is cumulative month-to-date, so we use metric math: sampling it at
# a 1-day period (Maximum = end-of-day cumulative) and taking DIFF() yields the
# day-over-day increase, i.e. what was actually spent that day. On the 1st of the month
# the metric resets, making DIFF negative for one day (below any positive threshold),
# so there is no false alarm.
# ===========================================================================
resource "aws_cloudwatch_metric_alarm" "daily_charges" {
  provider            = aws.us_east_1
  alarm_name          = "${var.name_prefix}-daily-estimated-charges"
  alarm_description   = "Estimated AWS charges for the day exceeded the configured threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.daily_cost_threshold_usd
  treat_missing_data  = "notBreaching"

  # e1 = day-over-day delta of cumulative estimated charges = today's spend.
  metric_query {
    id          = "e1"
    expression  = "DIFF(m1)"
    label       = "DailyEstimatedCharges"
    return_data = true
  }

  # m1 = cumulative month-to-date charges, sampled once per day (end-of-day value).
  metric_query {
    id          = "m1"
    return_data = false
    metric {
      namespace   = "AWS/Billing"
      metric_name = "EstimatedCharges"
      dimensions  = { Currency = "USD" }
      period      = 86400
      stat        = "Maximum"
    }
  }

  alarm_actions = [aws_sns_topic.alarms_use1.arn]
  ok_actions    = [aws_sns_topic.alarms_use1.arn]
  tags          = { Name = "${var.name_prefix}-daily-estimated-charges" }
}
