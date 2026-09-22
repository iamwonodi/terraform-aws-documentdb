# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
# Read for their availability zones, so the instances can be spread across them.
# count rather than for_each: the IDs may not be known until apply, their number
# always is.
# -----------------------------------------------------------------------------

data "aws_subnet" "this" {
  count = length(var.subnet_ids)

  id = var.subnet_ids[count.index]
}
