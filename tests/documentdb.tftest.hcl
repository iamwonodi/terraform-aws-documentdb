# Run with: terraform init -backend=false && terraform test   (no AWS access needed)

mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = { availability_zone = "af-south-1a" }
  }
}

variables {
  project_name               = "acme"
  environment                = "production"
  name                       = "mongodb"
  master_username            = "platformadmin"
  master_password            = "S3cret-pw.x-long-enough"
  vpc_id                     = "vpc-0abc"
  subnet_ids                 = ["subnet-0a", "subnet-0b", "subnet-0c"]
  allowed_security_group_ids = ["sg-0app"]
}

run "defaults_are_secure_and_smallest" {
  command = plan

  assert {
    condition     = aws_docdb_cluster.this.cluster_identifier == "acme-production-mongodb" && aws_docdb_cluster.this.engine == "docdb"
    error_message = "the cluster is named <project>-<environment>-<name>"
  }

  assert {
    condition     = aws_docdb_cluster.this.storage_encrypted && aws_docdb_cluster.this.deletion_protection && !aws_docdb_cluster.this.skip_final_snapshot
    error_message = "encrypted, deletion-protected, with a final snapshot by default"
  }

  assert {
    condition     = aws_docdb_cluster.this.backup_retention_period == 7 && aws_docdb_cluster.this.port == 27017
    error_message = "7 days of backups on MongoDB's port"
  }

  assert {
    condition     = length(aws_docdb_cluster_instance.this) == 1 && aws_docdb_cluster_instance.this[0].instance_class == "db.t4g.medium"
    error_message = "one instance of the smallest class"
  }

  assert {
    condition     = length(aws_docdb_cluster.this.serverless_v2_scaling_configuration) == 0
    error_message = "provisioned unless serverless is set"
  }

  assert {
    condition     = length(aws_docdb_cluster_parameter_group.this) == 0 && output.parameter_group_name == null
    error_message = "AWS's default parameter group (which enforces TLS) unless parameters are given"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_security_group["sg-0app"].from_port == 27017 && length(aws_vpc_security_group_ingress_rule.from_cidr) == 0
    error_message = "only the named security group may reach the port"
  }
}

# The zone each instance gets is covered where a test can give each subnet its
# own zone; a mocked provider gives them all one. Here: every instance is placed.
run "high_availability_names_orders_and_places_every_instance" {
  command = plan

  variables {
    instance_count = 3
  }

  assert {
    condition     = alltrue([for i in aws_docdb_cluster_instance.this : i.availability_zone == "af-south-1a"])
    error_message = "every instance is given a zone from the subnets"
  }

  assert {
    condition     = [for i in aws_docdb_cluster_instance.this : i.identifier] == ["acme-production-mongodb-1", "acme-production-mongodb-2", "acme-production-mongodb-3"]
    error_message = "instances are <identifier>-1, -2, ..."
  }

  assert {
    condition     = [for i in aws_docdb_cluster_instance.this : i.promotion_tier] == [0, 1, 2]
    error_message = "failover follows the instances' order"
  }
}

run "serverless" {
  command = plan

  variables {
    engine_version = "5.0.0"
    instance_count = 2
    serverless     = { min_capacity = 0.5, max_capacity = 4 }
  }

  assert {
    condition     = alltrue([for i in aws_docdb_cluster_instance.this : i.instance_class == "db.serverless"]) && output.instance_class == "db.serverless"
    error_message = "serverless instances are db.serverless"
  }

  assert {
    condition     = aws_docdb_cluster.this.serverless_v2_scaling_configuration[0].min_capacity == 0.5 && aws_docdb_cluster.this.serverless_v2_scaling_configuration[0].max_capacity == 4
    error_message = "the cluster carries the capacity range"
  }
}

run "serverless_on_an_old_engine_is_refused" {
  command = plan

  variables {
    engine_version = "4.0.0"
    serverless     = { min_capacity = 0.5, max_capacity = 4 }
  }

  expect_failures = [aws_docdb_cluster.this]
}

run "a_serverless_capacity_off_the_half_step_is_refused" {
  command = plan

  variables {
    serverless = { min_capacity = 0.3, max_capacity = 4 }
  }

  expect_failures = [var.serverless]
}

run "a_serverless_minimum_above_the_maximum_is_refused" {
  command = plan

  variables {
    serverless = { min_capacity = 8, max_capacity = 4 }
  }

  expect_failures = [var.serverless]
}

run "parameters_create_a_group_of_the_engines_family" {
  command = plan

  variables {
    engine_version                  = "5.0.0"
    cluster_parameters              = { audit_logs = { value = "enabled" } }
    enabled_cloudwatch_logs_exports = ["audit"]
  }

  assert {
    condition     = aws_docdb_cluster_parameter_group.this[0].family == "docdb5.0"
    error_message = "the family follows the engine's major.minor"
  }

  assert {
    condition     = one([for p in aws_docdb_cluster_parameter_group.this[0].parameter : p.apply_method if p.name == "audit_logs"]) == "pending-reboot"
    error_message = "parameters apply at the next reboot unless told otherwise"
  }
}

run "parameters_without_an_engine_version_are_refused" {
  command = plan

  variables {
    cluster_parameters = { audit_logs = { value = "enabled" } }
  }

  expect_failures = [aws_docdb_cluster_parameter_group.this]
}

run "an_own_group_and_parameters_together_are_refused" {
  command = plan

  variables {
    engine_version       = "5.0.0"
    cluster_parameters   = { audit_logs = { value = "enabled" } }
    parameter_group_name = "existing"
  }

  expect_failures = [aws_docdb_cluster.this]
}

run "an_underscore_in_the_username_is_refused" {
  command = plan

  variables {
    master_username = "platform_admin"
  }

  expect_failures = [var.master_username]
}

run "a_forbidden_password_character_is_refused" {
  command = plan

  variables {
    master_password = "has@sign-in-it"
  }

  expect_failures = [var.master_password]
}

run "an_unknown_log_export_is_refused" {
  command = plan

  variables {
    enabled_cloudwatch_logs_exports = ["slowquery"]
  }

  expect_failures = [var.enabled_cloudwatch_logs_exports]
}

run "no_backups_is_refused" {
  command = plan

  variables {
    backup_retention_period = 0
  }

  expect_failures = [var.backup_retention_period]
}

run "seventeen_instances_are_refused" {
  command = plan

  variables {
    instance_count = 17
  }

  expect_failures = [var.instance_count]
}

run "bringing_your_own_security_group" {
  command = plan

  variables {
    create_security_group      = false
    security_group_ids         = ["sg-0own"]
    allowed_security_group_ids = []
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && join(",", output.security_group_ids) == "sg-0own"
    error_message = "the caller's group is attached and none is created"
  }
}

run "no_security_group_at_all_is_refused" {
  command = plan

  variables {
    create_security_group      = false
    allowed_security_group_ids = []
  }

  expect_failures = [aws_docdb_cluster.this]
}
