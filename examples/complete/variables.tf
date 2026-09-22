# -----------------------------------------------------------------------------
# AWS Region
# -----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS Region where the example resources will be created. DocumentDB is not offered in every Region."
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Project name used in the cluster's identifier and the secret's name."
  default     = "example"
}

variable "environment" {
  type        = string
  description = "Environment name used in the cluster's identifier."
  default     = "production"
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the cluster will live in."

  validation {
    condition     = trimspace(var.vpc_id) != ""
    error_message = "vpc_id must not be empty."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "IDs of at least two subnets, in different availability zones, for the subnet group. Private or isolated subnets: a database needs no route to the internet."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "IDs of the security groups whose instances may reach the cluster, for example the application tier's."

  validation {
    condition     = length(var.allowed_security_group_ids) > 0
    error_message = "allowed_security_group_ids must name at least one group, or nothing could connect."
  }
}
