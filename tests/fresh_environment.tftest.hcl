# Run with: terraform init -backend=false && terraform test   (no AWS access needed)
#
# The module must plan when the IDs it is given are created in the same apply,
# as they are in a fresh environment. A for_each keyed by those IDs fails the
# plan with "Invalid for_each argument"; this test catches that.

mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = { availability_zone = "af-south-1a" }
  }
}

run "plans_with_ids_created_in_the_same_apply" {
  command = plan

  module {
    source = "./tests/fresh-environment"
  }
}
