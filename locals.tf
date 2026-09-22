locals {
  name = coalesce(var.name, "docdb")

  # Identifiers allow lowercase letters, digits and single hyphens, must begin
  # with a letter, and are at most 63 characters. 60 leaves room for the instance
  # suffix (-16). The generated one is normalised so that a project or
  # environment containing anything else still produces a valid identifier.
  generated_identifier = substr(
    trim(
      replace(lower("${var.project_name}-${var.environment}-${local.name}"), "/[^a-z0-9]+/", "-"),
      "-",
    ),
    0,
    60,
  )

  identifier = coalesce(var.identifier, local.generated_identifier)

  is_serverless  = var.serverless != null
  instance_class = local.is_serverless ? "db.serverless" : var.instance_class

  # A parameter group's family is "docdb" plus the engine's major.minor
  # ("5.0.0" -> "docdb5.0"). Needed only when this module creates the group.
  engine_major_minor     = var.engine_version == null ? null : join(".", slice(split(".", var.engine_version), 0, 2))
  parameter_group_family = local.engine_major_minor == null ? null : "docdb${local.engine_major_minor}"

  create_parameter_group = length(var.cluster_parameters) > 0

  parameter_group_name = local.create_parameter_group ? aws_docdb_cluster_parameter_group.this[0].name : var.parameter_group_name

  # The snapshot's name carries a timestamp so that destroying, recreating and
  # destroying again does not collide with the first snapshot. It is read only
  # when the cluster is destroyed, and ignored in the plan (see main.tf).
  final_snapshot_identifier = var.skip_final_snapshot ? null : coalesce(
    var.final_snapshot_identifier,
    "${local.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}",
  )

  security_group_ids = concat(
    var.create_security_group ? [aws_security_group.this[0].id] : [],
    var.security_group_ids,
  )

  # The subnets' zones, in the order the subnets were given, without repeats.
  # Instance N goes to zone N modulo their number, so a second instance lands in
  # a second zone and can take over if the first zone fails.
  availability_zones = distinct([for subnet in data.aws_subnet.this : subnet.availability_zone])

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
