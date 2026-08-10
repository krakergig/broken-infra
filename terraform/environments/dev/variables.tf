# environments/dev/variables.tf
# Input variables for the dev environment.

variable "region" {
  description = "AWS region for all resources. Challenge mandates Frankfurt."
  type        = string
  default     = "eu-central-1"
}

# Object-typed tags with optional attributes + defaults (challenge requirement #7).
variable "tags" {
  description = "Standard tag set applied to every resource through provider default_tags."
  type = object({
    environment = optional(string, "develop")
    product     = optional(string, "cloud")
    service     = optional(string, "pipeline")
  })
  default = {}
}

variable "app_vpc_cidr" {
  description = "CIDR block for the application VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "jenkins_vpc_cidr" {
  description = "CIDR block for the Jenkins VPC."
  type        = string
  default     = "10.41.0.0/16"
}

variable "app_image" {
  description = "Container image for the public-facing application."
  type        = string
  default     = "infrastructureascode/hello-world:latest"
}

variable "jenkins_image" {
  description = "Container image for Jenkins."
  type        = string
  default     = "jenkins/jenkins:lts"
}

variable "instance_type" {
  description = "EC2 instance type for ECS container hosts. t3.micro is free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "instances_per_cluster" {
  description = "Number of EC2 container-host instances per ECS cluster."
  type        = number
  default     = 2
}

variable "alarm_email" {
  description = "Email address subscribed to the SNS alarm topics. Confirm manually."
  type        = string
  default     = "cloud-ops@example.com"
}

variable "jenkins_allowed_countries" {
  description = "ISO 3166-1 alpha-2 country codes permitted to reach the Jenkins ALB."
  type        = list(string)
  default     = ["PT"]
}

variable "daily_cost_threshold_usd" {
  description = "Estimated-charges threshold (USD) that trips the CloudWatch cost alarm."
  type        = number
  default     = 1
}
