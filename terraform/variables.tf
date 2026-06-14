variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro is free tier eligible in eu-west-3)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the AWS key pair (must exist in the target region)"
  type        = string
  default     = "cloud-1-key"
}

variable "ssh_private_key_path" {
  description = "Local path to the SSH private key file for Ansible"
  type        = string
  default     = "~/.ssh/cloud-1-key.pem"
}

variable "my_ip" {
  description = "Local IP in CIDR notation (e.g. 1.2.3.4/32) — restricts SSH access to my machine"
  type        = string
}

# Web ASG sizing -----------------------------------------------------------------------------
variable "web_min_size" {
  description = "Minimum number of web instances (evaluation requires >= 2)"
  type        = number
  default     = 2
}

variable "web_desired" {
  description = "Desired number of web instances"
  type        = number
  default     = 2
}

variable "web_max_size" {
  description = "Maximum number of web instances (for scalability demo)"
  type        = number
  default     = 4
}

# Database credentials (store in terraform.tfvars — we never commit that file) ---------------
variable "db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpress"
}

variable "db_user" {
  description = "WordPress database user"
  type        = string
  default     = "wordpress_user"
}

variable "db_password" {
  description = "WordPress database password"
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "MariaDB root password"
  type        = string
  sensitive   = true
}

# DuckDNS (optional) -------------------------------------------------------------------------
variable "duckdns_token" {
  description = "DuckDNS token for DNS update (optional, leave empty to skip)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "duckdns_subdomain" {
  description = "DuckDNS subdomain (without .duckdns.org)"
  type        = string
  default     = "mlezcano-cloud1"
}

# Project prefix for resource naming ----------------------------------------------------------
variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "cloud1"
}

# WordPress auto-install credentials (used by WP-CLI in cloud-init) ---------------------------
variable "wp_title" {
  description = "WordPress site title"
  type        = string
  default     = "Cloud-1"
}

variable "wp_admin_user" {
  description = "WordPress admin username"
  type        = string
  default     = "admin"
}

variable "wp_admin_password" {
  description = "WordPress admin password"
  type        = string
  sensitive   = true
}

variable "wp_admin_email" {
  description = "WordPress admin email"
  type        = string
  default     = "admin@example.com"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to disable)"
  type        = string
  default     = ""
}
