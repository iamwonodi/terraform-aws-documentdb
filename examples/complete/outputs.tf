# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

output "endpoint" {
  description = "Writer endpoint applications connect to."
  value       = module.documentdb.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint, for reads that tolerate slight replication lag."
  value       = module.documentdb.reader_endpoint
}

output "port" {
  description = "Port the cluster accepts connections on."
  value       = module.documentdb.port
}

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

output "identifier" {
  description = "The cluster's identifier."
  value       = module.documentdb.id
}

output "instance_availability_zones" {
  description = "Where each instance runs, writer first."
  value       = module.documentdb.instance_availability_zones
}

# -----------------------------------------------------------------------------
# Credential
# -----------------------------------------------------------------------------

output "admin_secret_arn" {
  description = "ARN of the secret holding the administrator credential. The credential belongs to this configuration, not to the module."
  value       = aws_secretsmanager_secret.master.arn
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "The security group the module created for the cluster."
  value       = module.documentdb.security_group_id
}
