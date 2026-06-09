# terraform/variables.tf

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for tagging and naming resources"
  type        = string
  default     = "minecraft"
}

variable "key_name" {
  description = "Name for the AWS key pair"
  type        = string
  default     = "minecraft-key"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type — t3.medium minimum recommended for Minecraft"
  type        = string
  default     = "t3.medium"
}

variable "volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into the instance. Restrict to your IP in production."
  type        = string
  default     = "0.0.0.0/0"
}
