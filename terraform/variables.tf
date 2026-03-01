variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type (t2.small = 2GB RAM, minimum for OpenClaw)"
  type        = string
  default     = "t2.small"
}

variable "key_name" {
  description = "Name for the SSH key pair"
  type        = string
  default     = "openclaw-server-key"
}

variable "admin_domain" {
  description = "Domain for the admin panel (optional, configure HTTPS from the admin panel guide)"
  type        = string
  default     = ""
}
