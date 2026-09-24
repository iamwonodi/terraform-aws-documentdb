# A fresh environment: the subnets and the callers' security groups are created
# in the same apply as the cluster, so their IDs are unknown when the plan is
# made. terraform_data stands in for them.
#
# Unknown subnets also keep the plan off AWS: the module's subnet lookup is
# deferred to apply, so no real subnet is needed even if the provider is real.
resource "terraform_data" "subnet" {
  for_each = toset(["a", "b", "c"])
  input    = each.key
}

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
  subnet_ids      = [for key in ["a", "b", "c"] : terraform_data.subnet[key].id]

  allowed_security_group_ids = [terraform_data.caller.id, "sg-0existing"]
}
