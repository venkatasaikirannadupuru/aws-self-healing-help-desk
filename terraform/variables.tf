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
  description = "Existing image tag in ECR. Jenkins publishes latest."
  type        = string
  default     = "latest"
}
variable "desired_capacity" {
  description = "Desired number of app instances. Set to 0 during initial ECR bootstrap."
  type        = number
  default     = 1
  validation {
    condition     = var.desired_capacity >= 0 && var.desired_capacity <= 2
    error_message = "desired_capacity must be between 0 and 2 for this demo."
  }
}
