# -----------------------------------------------------------------------------
# Amazon DocumentDB Cluster
# -----------------------------------------------------------------------------
# Creates one Amazon DocumentDB (MongoDB-compatible) instance-based cluster: its
# subnet group, optionally its security group and parameter group, the cluster,
# and its instances.
#
# A DocumentDB cluster separates storage from compute. The CLUSTER owns the data,
# always stored six ways across three availability zones; the INSTANCES are the
# compute that serves it, one writer and up to fifteen readers. Readers take over
# if the writer fails, so high availability means two or more instances, spread
# across zones -- and each is billed.
#
# Capacity is provisioned (instance_class) or serverless (serverless). Both are
# instance-based clusters; DocumentDB Elastic Clusters are a different service
# and resource, and not covered here.
#
# The administrator credential is an input. The module neither generates nor
# stores it, so the caller keeps it with its other secrets and this module never
# becomes the owner of one.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Subnet Group
# -----------------------------------------------------------------------------

resource "aws_docdb_subnet_group" "this" {
  name        = local.identifier
  description = "Subnets for ${local.identifier}."
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, { Name = local.identifier })
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Created unless the caller brings its own. It has no egress rules: a database
# answers connections and makes none of its own.
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  count = var.create_security_group ? 1 : 0

  name        = "${local.identifier}-docdb"
  description = "DocumentDB cluster ${local.identifier}."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.identifier}-docdb" })

  lifecycle {
    create_before_destroy = true
  }
}

# Rules are separate resources rather than inline blocks: inline rules replace
# the whole set on every change, which would drop a rule another configuration
# added.
resource "aws_vpc_security_group_ingress_rule" "from_security_group" {
  for_each = var.create_security_group ? toset(var.allowed_security_group_ids) : []

  security_group_id            = aws_security_group.this[0].id
  referenced_security_group_id = each.value

  description = "Allow ${each.value} to reach ${local.identifier}."

  ip_protocol = "tcp"
  from_port   = var.port
  to_port     = var.port

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = var.create_security_group ? toset(var.allowed_cidr_blocks) : []

  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.value

  description = "Allow ${each.value} to reach ${local.identifier}."

  ip_protocol = "tcp"
  from_port   = var.port
  to_port     = var.port

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cluster Parameter Group
# -----------------------------------------------------------------------------
# Only when parameters are given. AWS's default group already enforces TLS
# (tls = enabled), so most callers need none.
# -----------------------------------------------------------------------------

resource "aws_docdb_cluster_parameter_group" "this" {
  count = local.create_parameter_group ? 1 : 0

  name_prefix = "${local.identifier}-"
  description = "Parameters for ${local.identifier}."
  family      = local.parameter_group_family

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = local.common_tags

  # A new group (a family change, say) is created before the old one is
  # released, since the cluster cannot be left without one.
  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.engine_version != null
      error_message = "cluster_parameters creates a parameter group, whose family comes from engine_version. Set engine_version (for example \"5.0.0\")."
    }
  }
}

# -----------------------------------------------------------------------------
# The Cluster
# -----------------------------------------------------------------------------

resource "aws_docdb_cluster" "this" {
  cluster_identifier = local.identifier

  # ---------------------------------------------------------------------------
  # Engine
  # ---------------------------------------------------------------------------

  engine                          = "docdb"
  engine_version                  = var.engine_version
  allow_major_version_upgrade     = var.allow_major_version_upgrade
  db_cluster_parameter_group_name = local.parameter_group_name

  # ---------------------------------------------------------------------------
  # Administrator
  # ---------------------------------------------------------------------------
  # Supplied by the caller. manage_master_user_password is deliberately not used:
  # it would create a secret this module does not control, which the caller then
  # has to discover rather than own.
  # ---------------------------------------------------------------------------

  master_username = var.master_username
  master_password = var.master_password

  # ---------------------------------------------------------------------------
  # Capacity
  # ---------------------------------------------------------------------------
  # The cluster holds the serverless range; each db.serverless instance scales
  # within it.
  # ---------------------------------------------------------------------------

  dynamic "serverless_v2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverless] : []

    content {
      min_capacity = serverless_v2_scaling_configuration.value.min_capacity
      max_capacity = serverless_v2_scaling_configuration.value.max_capacity
    }
  }

  # ---------------------------------------------------------------------------
  # Storage
  # ---------------------------------------------------------------------------

  storage_type      = var.storage_type
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # ---------------------------------------------------------------------------
  # Network
  # ---------------------------------------------------------------------------

  port                   = var.port
  db_subnet_group_name   = aws_docdb_subnet_group.this.name
  vpc_security_group_ids = local.security_group_ids

  # ---------------------------------------------------------------------------
  # Backups, maintenance and deletion
  # ---------------------------------------------------------------------------

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, { Name = local.identifier })

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------
  # These depend on more than one variable, so they cannot live in variables.tf.
  # They are preconditions rather than check blocks: a failed check only warns
  # and lets the apply continue.
  # ---------------------------------------------------------------------------

  lifecycle {
    # The generated snapshot name contains a timestamp, which would otherwise
    # differ on every plan. It is read only when the cluster is destroyed.
    ignore_changes = [final_snapshot_identifier]

    precondition {
      condition     = !(local.create_parameter_group && var.parameter_group_name != null)
      error_message = "Set cluster_parameters (this module creates the group) or parameter_group_name (an existing group), not both."
    }

    precondition {
      condition     = !local.is_serverless || var.engine_version == null || tonumber(split(".", coalesce(var.engine_version, "5.0.0"))[0]) >= 5
      error_message = "DocumentDB serverless needs engine version 5.0.0 or later; engine_version is ${coalesce(var.engine_version, "unset")}."
    }

    precondition {
      condition     = var.create_security_group || length(var.security_group_ids) > 0
      error_message = "create_security_group is false, so security_group_ids must name at least one existing group; a cluster with none is unreachable."
    }

    precondition {
      condition     = var.create_security_group || (length(var.allowed_security_group_ids) == 0 && length(var.allowed_cidr_blocks) == 0)
      error_message = "allowed_security_group_ids and allowed_cidr_blocks describe rules on the security group this module creates, and create_security_group is false. Put the rules on the groups you supplied instead."
    }
  }
}

# -----------------------------------------------------------------------------
# Instances
# -----------------------------------------------------------------------------
# Instance 1 is created as the writer; the rest are readers. promotion_tier
# follows the order, so on a failure the next instance in line takes over. Each
# is placed in the next of the subnets' zones.
# -----------------------------------------------------------------------------

resource "aws_docdb_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${local.identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.this.id

  instance_class    = local.instance_class
  availability_zone = local.availability_zones[count.index % length(local.availability_zones)]
  promotion_tier    = min(count.index, 15)

  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  preferred_maintenance_window = var.maintenance_window
  ca_cert_identifier           = var.ca_cert_identifier

  enable_performance_insights = var.performance_insights_enabled

  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, { Name = "${local.identifier}-${count.index + 1}" })
}
