# modules/ecs_service/variables.tf
# Inputs for the reusable ECS-on-EC2 service module. The same module deploys both the
# hello-world application and the Jenkins controller (challenge requirement #3).

variable "name" {
  description = "Logical name for this service (used as a prefix for all resources)."
  type        = string
}

variable "region" {
  description = "AWS region (used for the awslogs driver region option)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and ALB live in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets hosting the EC2 container instances and tasks."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets hosting the internet-facing ALB."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for the container hosts."
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of EC2 container instances in the cluster."
  type        = number
  default     = 2
}

variable "image" {
  description = "Container image to run."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
}

variable "desired_count" {
  description = "Number of task copies the service should keep running."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "CPU units reserved for the task (1024 = 1 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory (MiB) reserved for the task."
  type        = number
  default     = 512
}

variable "extra_ebs_volume_size_gb" {
  description = "Size (GiB) of an extra EBS data volume attached to each container host. 0 disables it. When > 0 the host formats it and mounts it at /data."
  type        = number
  default     = 0
}

variable "extra_ebs_volume_device_name" {
  description = "Block device name for the optional extra EBS volume."
  type        = string
  default     = "/dev/xvdb"
}

variable "task_role_arn" {
  description = "ECS task role ARN (application/pipeline permissions), supplied by the caller."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener."
  type        = string
}

variable "log_bucket" {
  description = "S3 bucket name for ALB access logs."
  type        = string
}

variable "health_check_path" {
  description = "HTTP path the ALB target group uses for health checks."
  type        = string
  default     = "/"
}

variable "container_environment" {
  description = "Extra environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "extra_tags" {
  description = "Additional resource-specific tags (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}
