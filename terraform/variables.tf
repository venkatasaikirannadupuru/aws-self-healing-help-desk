variable "aws_region" {
  description = "AWS region for the Help Desk infrastructure."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "self-healing-help-desk"
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type for the application nodes."
  type        = string
  default     = "t3.micro"
}

variable "image_tag" {
  description = "ECR image tag pulled by EC2 user data. Jenkins publishes the latest tag."
  type        = string
  default     = "latest"
}

variable "desired_capacity" {
  description = "Initial number of app instances. Start at zero until Jenkins has pushed the latest image."
  type        = number
  default     = 0

  validation {
    condition     = var.desired_capacity >= 0 && var.desired_capacity <= 2
    error_message = "desired_capacity must be between 0 and 2 for this demo."
  }
}
