# -----------------------------------------------------------------------------
# Complete Example
# -----------------------------------------------------------------------------
# Shows the module as a production caller would use it:
#
#   - the administrator password generated and stored by the CALLER, since the
#     module neither generates nor stores one;
#   - two instances, spread across availability zones, so a reader takes over
#     if the writer fails;
#   - storage encrypted, backups kept, deletion protected;
#   - reachable only from the security groups named, on MongoDB's port;
#   - audit logging enabled through a parameter and published to CloudWatch.
#
# It creates a real DocumentDB cluster, which costs money. Destroying it needs
# deletion_protection cleared first, which is the point of that default.
#
# For serverless capacity instead, replace instance_class with
#   serverless = { min_capacity = 0.5, max_capacity = 8 }
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# The administrator credential
# -----------------------------------------------------------------------------
# DocumentDB rejects /, " and @ in a password, and a value that travels through
# env files and connection strings is easier to handle without other
# punctuation, so the alphabet is narrowed rather than left to chance. The user
# name may contain letters and digits only.
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "-_."
}

locals {
  master_username = "${replace(var.project_name, "/[^A-Za-z0-9]/", "")}admin"
}

resource "aws_secretsmanager_secret" "master" {
  name        = "${var.project_name}-${var.environment}-documentdb-admin"
  description = "Administrator credential for the ${var.project_name} ${var.environment} DocumentDB cluster."
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id

  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master.result
    engine   = "docdb"
    host     = module.documentdb.endpoint
    port     = module.documentdb.port
  })
}

# -----------------------------------------------------------------------------
# The cluster
# -----------------------------------------------------------------------------

module "documentdb" {
  source = "../../"

  project_name = var.project_name
  environment  = var.environment
  name         = "mongodb"

  engine_version = "5.0.0"

  master_username = local.master_username
  master_password = random_password.master.result

  instance_count = 2
  instance_class = "db.t4g.medium"

  storage_encrypted = true

  backup_retention_period = 14
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"

  deletion_protection = true
  skip_final_snapshot = false

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  allowed_security_group_ids = var.allowed_security_group_ids

  cluster_parameters = {
    audit_logs = { value = "enabled" }
  }
  enabled_cloudwatch_logs_exports = ["audit"]

  tags = {
    Component = "Database"
  }
}
