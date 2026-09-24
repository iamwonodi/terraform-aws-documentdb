# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Project the cluster belongs to. Part of its identifier."

  validation {
    condition     = trimspace(var.project_name) != ""
    error_message = "project_name must not be empty."
  }
}

variable "environment" {
  type        = string
  description = "Environment the cluster belongs to. Part of its identifier."

  validation {
    condition     = trimspace(var.environment) != ""
    error_message = "environment must not be empty."
  }
}

variable "name" {
  type        = string
  default     = null
  description = "Distinguishes this cluster from another in the same project and environment. Defaults to \"docdb\"."

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]*$", coalesce(var.name, "x")))
    error_message = "name must be lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "identifier" {
  type        = string
  default     = null
  description = "The cluster's identifier, overriding the generated <project>-<environment>-<name>. Instances are named <identifier>-1, -2 and so on. AWS allows 1-63 characters: lowercase letters, digits and hyphens, beginning with a letter, with no two hyphens together and no trailing hyphen; identifiers are unique across RDS, Neptune and DocumentDB in an account and Region."

  validation {
    condition     = var.identifier == null || can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", coalesce(var.identifier, "x")))
    error_message = "identifier must begin with a letter and contain only lowercase letters, digits and single hyphens."
  }

  validation {
    condition     = var.identifier == null || length(coalesce(var.identifier, "x")) <= 60
    error_message = "identifier must be at most 60 characters, leaving room for the instance suffix (-1 ... -16) within AWS's 63."
  }
}

# -----------------------------------------------------------------------------
# Engine
# -----------------------------------------------------------------------------

variable "engine_version" {
  type        = string
  default     = null
  description = "DocumentDB engine version, for example \"5.0.0\" or \"8.0.0\". Null lets AWS choose its current default. Pin it once a project depends on a version's behaviour. Serverless needs 5.0.0 or later."

  validation {
    condition     = var.engine_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.engine_version, "x")))
    error_message = "engine_version must look like 5.0.0."
  }
}

variable "allow_major_version_upgrade" {
  type        = bool
  default     = false
  description = "Allow a change of engine_version to a new major version. Off, so a major upgrade is always a deliberate change."
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Apply minor engine upgrades automatically in the maintenance window."
}

variable "port" {
  type        = number
  default     = 27017
  description = "Port the cluster accepts connections on. 27017 is MongoDB's own, so clients need no port configured."

  validation {
    condition     = var.port == floor(var.port) && var.port >= 1 && var.port <= 65535
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "cluster_parameters" {
  type = map(object({
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default     = {}
  description = "Cluster parameters to set, by name, for example { audit_logs = { value = \"enabled\" } }. Empty uses AWS's default parameter group, which already enforces TLS. Non-empty creates this cluster's own group; its family comes from engine_version, which must then be set."

  validation {
    condition     = alltrue([for p in values(var.cluster_parameters) : contains(["immediate", "pending-reboot"], p.apply_method)])
    error_message = "apply_method must be \"immediate\" or \"pending-reboot\"."
  }
}

variable "parameter_group_name" {
  type        = string
  default     = null
  description = "An existing cluster parameter group to use instead. Cannot be combined with cluster_parameters."
}

# -----------------------------------------------------------------------------
# Administrator
#
# The module does NOT generate or store the credential. The caller owns it, so
# it can be generated, stored and rotated with the project's other secrets, and
# this module never becomes the owner of one.
# -----------------------------------------------------------------------------

variable "master_username" {
  type        = string
  description = "The administrator's user name. It cannot be changed after creation. DocumentDB allows 1-63 letters or digits, beginning with a letter: no underscores, unlike RDS. DocumentDB also refuses words reserved by its engine."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,62}$", var.master_username))
    error_message = "master_username must be 1-63 letters or digits, beginning with a letter (DocumentDB accepts no underscores or other punctuation)."
  }
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "The administrator's password. Generate and store it in the calling configuration; this module only passes it to DocumentDB, which requires 8 to 100 printable characters and forbids /, \" and @."

  validation {
    condition     = length(var.master_password) >= 8 && length(var.master_password) <= 100
    error_message = "master_password must be between 8 and 100 characters."
  }

  validation {
    condition     = !can(regex("[/\"@ ]", var.master_password))
    error_message = "master_password must not contain a slash, a double quote, an at sign or a space: DocumentDB rejects them."
  }
}

# -----------------------------------------------------------------------------
# Capacity
#
# Provisioned: instance_count instances of instance_class, billed per hour.
# Serverless: set serverless; each instance scales between its minimum and
# maximum capacity (DCUs), billed per DCU-hour. There is no scale to zero: the
# minimum is billed continuously.
# -----------------------------------------------------------------------------

variable "instance_count" {
  type        = number
  default     = 1
  description = "Instances in the cluster: one writer, the rest readers that take over if the writer fails. 1 is a single point of failure (the data itself is always stored in three availability zones); 2 or more spread across zones is highly available. Each instance is billed."

  validation {
    condition     = var.instance_count == floor(var.instance_count) && var.instance_count >= 1 && var.instance_count <= 16
    error_message = "instance_count must be a whole number from 1 to 16."
  }
}

variable "instance_class" {
  type        = string
  default     = "db.t4g.medium"
  description = "Instance class for provisioned capacity. The default is the smallest DocumentDB offers. Ignored when serverless is set (the class is then db.serverless)."

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like db.t4g.medium."
  }
}

variable "serverless" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default     = null
  description = "Serverless capacity, in DocumentDB capacity units (about 2 GiB of memory each), per instance: 0.5 to 256 in steps of 0.5. Null uses provisioned instances. The minimum is billed continuously."

  validation {
    condition = var.serverless == null || (
      try(var.serverless.min_capacity >= 0.5 && var.serverless.max_capacity <= 256 && var.serverless.min_capacity <= var.serverless.max_capacity, false)
    )
    error_message = "serverless capacity must satisfy 0.5 <= min_capacity <= max_capacity <= 256."
  }

  validation {
    condition = var.serverless == null || (
      try(var.serverless.min_capacity * 2 == floor(var.serverless.min_capacity * 2) && var.serverless.max_capacity * 2 == floor(var.serverless.max_capacity * 2), false)
    )
    error_message = "serverless capacities must be in steps of 0.5."
  }
}

# -----------------------------------------------------------------------------
# Storage and encryption
# -----------------------------------------------------------------------------

variable "storage_type" {
  type        = string
  default     = "standard"
  description = "\"standard\" bills storage I/O per request; \"iopt1\" (I/O-Optimized) includes I/O in a higher instance and storage price, which pays off only for I/O-heavy workloads."

  validation {
    condition     = contains(["standard", "iopt1"], var.storage_type)
    error_message = "storage_type must be \"standard\" or \"iopt1\"."
  }
}

variable "storage_encrypted" {
  type        = bool
  default     = true
  description = "Encrypt the cluster's storage, backups and snapshots. It cannot be changed after creation."
}

variable "kms_key_id" {
  type        = string
  default     = null
  description = "ARN of a customer-managed KMS key for encryption. Null uses the account's AWS-managed key."
}

# -----------------------------------------------------------------------------
# Backups, maintenance and deletion
# -----------------------------------------------------------------------------

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Days of automated backups, 1 to 35. DocumentDB cannot turn them off."

  validation {
    condition     = var.backup_retention_period == floor(var.backup_retention_period) && var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be a whole number from 1 to 35."
  }
}

variable "backup_window" {
  type        = string
  default     = null
  description = "Daily UTC window for automated backups, hh24:mi-hh24:mi, at least 30 minutes and not overlapping maintenance_window. Null lets AWS choose."

  validation {
    condition     = var.backup_window == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", coalesce(var.backup_window, "x")))
    error_message = "backup_window must look like 03:00-03:30."
  }
}

variable "maintenance_window" {
  type        = string
  default     = null
  description = "Weekly UTC window for maintenance, ddd:hh24:mi-ddd:hh24:mi. Null lets AWS choose."

  validation {
    condition     = var.maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", coalesce(var.maintenance_window, "x")))
    error_message = "maintenance_window must look like sun:04:00-sun:05:00."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Refuse to delete the cluster. On by default: a destroy must first turn it off, which makes deleting a database a two-step decision."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Delete without a final snapshot. False by default, so deleting the cluster keeps a copy of its data."
}

variable "final_snapshot_identifier" {
  type        = string
  default     = null
  description = "Name of the final snapshot. Null generates <identifier>-final-<timestamp>."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply changes at once rather than in the maintenance window. Some changes restart the instances."
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "VPC the cluster lives in. Used for the security group this module creates."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the subnet group, in at least two availability zones. Instances are spread across these subnets' zones in order, so a reader takes over from another zone."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets, in different availability zones."
  }
}

variable "create_security_group" {
  type        = bool
  default     = true
  description = "Create a security group for the cluster. Set false to attach existing ones through security_group_ids."
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Existing security groups to attach, in addition to the one this module creates (if any)."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to reach the cluster's port. Preferred over CIDRs: it follows the callers as their instances change."

  validation {
    condition     = length(distinct(var.allowed_security_group_ids)) == length(var.allowed_security_group_ids)
    error_message = "allowed_security_group_ids must not list the same security group twice."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks allowed to reach the cluster's port. Use only where a security group cannot express the source."

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}

variable "ca_cert_identifier" {
  type        = string
  default     = null
  description = "Certificate authority for the instances' TLS certificates, for example rds-ca-rsa2048-g1. Null uses the Region's current default. Rotating it restarts the instances."
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  default     = []
  description = "Logs to publish to CloudWatch: \"audit\" and \"profiler\". Each also needs its cluster parameter (audit_logs, profiler) enabled through cluster_parameters, and CloudWatch bills for what is stored."

  validation {
    condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(["audit", "profiler"], log)])
    error_message = "enabled_cloudwatch_logs_exports may contain only \"audit\" and \"profiler\"."
  }
}

variable "performance_insights_enabled" {
  type        = bool
  default     = false
  description = "Performance Insights on each instance. Its free tier keeps 7 days; on a serverless instance it also consumes capacity."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}
