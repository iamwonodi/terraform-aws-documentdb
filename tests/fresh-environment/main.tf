# A fresh environment: the callers' security groups are created in the same
# apply as the cluster, so their IDs are unknown when the plan is made.
# terraform_data stands in for them.
resource "terraform_data" "caller" {
  input = "caller"
}

module "under_test" {
  source = "../.."

  project_name    = "acme"
  environment     = "production"
  name            = "mongodb"
  master_username = "platformadmin"
  master_password = "S3cret-pw.x-long-enough"
  vpc_id          = "vpc-0abc"
  subnet_ids      = ["subnet-0a", "subnet-0b", "subnet-0c"]

  allowed_security_group_ids = [terraform_data.caller.id, "sg-0existing"]
}
