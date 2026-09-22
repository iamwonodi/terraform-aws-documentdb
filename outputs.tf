# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

output "id" {
  description = "The cluster's identifier."
  value       = aws_docdb_cluster.this.id
}

output "arn" {
  description = "ARN of the cluster."
  value       = aws_docdb_cluster.this.arn
}

output "cluster_resource_id" {
  description = "The cluster's immutable resource ID (cluster-XXXX). It survives a rename."
  value       = aws_docdb_cluster.this.cluster_resource_id
}

output "engine_version" {
  description = "The engine version running, which AWS chooses when engine_version is null."
  value       = aws_docdb_cluster.this.engine_version
}

# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

output "endpoint" {
  description = "The writer endpoint. It follows the writer through a failover, so applications connect here."
  value       = aws_docdb_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "The reader endpoint, spreading reads across the readers (the writer itself when there are none)."
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the cluster accepts connections on."
  value       = aws_docdb_cluster.this.port
}

output "master_username" {
  description = "The administrator's user name."
  value       = aws_docdb_cluster.this.master_username
}

# -----------------------------------------------------------------------------
# Instances
# -----------------------------------------------------------------------------

output "instance_ids" {
  description = "Identifiers of the instances, writer first."
  value       = aws_docdb_cluster_instance.this[*].identifier
}

output "instance_endpoints" {
  description = "Each instance's own endpoint. Applications use endpoint or reader_endpoint instead; these are for diagnosis."
  value       = aws_docdb_cluster_instance.this[*].endpoint
}

output "instance_availability_zones" {
  description = "The availability zone of each instance, writer first."
  value       = aws_docdb_cluster_instance.this[*].availability_zone
}

output "instance_class" {
  description = "The instances' class: db.serverless when serverless is set."
  value       = local.instance_class
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the security group this module created, or null when it created none."
  value       = try(aws_security_group.this[0].id, null)
}

output "security_group_ids" {
  description = "Every security group attached to the cluster."
  value       = local.security_group_ids
}

output "subnet_group_name" {
  description = "Name of the subnet group."
  value       = aws_docdb_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Name of the cluster parameter group this module created or was given; null for AWS's default."
  value       = local.parameter_group_name
}
