# Terraform AWS DocumentDB

Reusable Terraform module for one **Amazon DocumentDB (with MongoDB compatibility)** instance-based cluster: its subnet group, optionally its security group and parameter group, the cluster, and its instances. Capacity is **provisioned** (an instance class) or **serverless** (a capacity range).

```text
            application (MongoDB driver, TLS)
                        |
                        | 27017, from the allowed security groups only
                        v
   +------------------------------------------------+
   |  cluster  <identifier>                          |
   |                                                 |
   |   instance -1 (writer)    instance -2 (reader)  |   one per zone, in the
   |   zone a                  zone b          ...   |   subnets' order
   |                                                 |
   |   storage: one volume, six copies, three zones  |
   +------------------------------------------------+
```

The module does not create the VPC, the subnets, or the administrator credential. The consuming configuration decides where the cluster lives, who may reach it, and where its credential is kept.

---

# What a DocumentDB cluster is

A cluster separates **storage** from **compute**:

* **The cluster** owns the data: one storage volume, always copied six ways across three availability zones, whatever the number of instances. Backups, encryption and the endpoints belong to the cluster.
* **The instances** serve it: one writer and up to fifteen readers. If the writer fails, a reader is promoted, and the cluster's `endpoint` follows it.

So **high availability means two or more instances in different zones**, and each instance is billed. With one instance the data is still safe, but a failure means waiting for the instance to be replaced.

It is an **instance-based** cluster. DocumentDB Elastic Clusters are a different service with a different resource, and are not covered here.

---

# Provisioned or serverless

| | Provisioned | Serverless |
| --- | --- | --- |
| Set | `instance_class` (default `db.t4g.medium`, the smallest) | `serverless = { min_capacity, max_capacity }` |
| Billed | per instance-hour | per DCU-hour, each instance between its minimum and maximum |
| Idle cost | the whole instance | the minimum (0.5 DCU at the lowest), continuously: there is no scale to zero |
| Engine | any | 5.0.0 or later |

A DCU is about 2 GiB of memory with its CPU and networking. Serverless tends to be cheaper for a light or bursty load and dearer for a steady heavy one. Either kind of cluster can be stopped for up to 7 days to stop the compute charge (storage is still billed); this module does not schedule that.

---

# Features

* One cluster and `instance_count` instances (1 to 16), writer first, failover in order
* Instances spread across the subnets' availability zones automatically
* Provisioned or serverless capacity
* Security group created by default, with separate ingress rules from named security groups or CIDRs; or bring your own
* No parameter group unless parameters are given (AWS's default already enforces TLS); family derived from the engine version
* Encryption at rest by default, optionally with a customer-managed KMS key
* Deletion protection and a final snapshot by default
* Automated backups, 1 to 35 days (DocumentDB cannot turn them off)
* Audit and profiler logs exportable to CloudWatch
* Standard or I/O-Optimized storage
* The administrator credential is an input, never generated or stored here
* Validation of DocumentDB's own naming, password and capacity rules at plan time

---

# Requirements

| Requirement | Version |
| --- | --- |
| Terraform | `>= 1.6.0` (`terraform test` needs 1.7 or later) |
| AWS Provider | `>= 6.0.0, < 7.0.0` |

---

# Usage

## Minimal

```hcl
module "documentdb" {
  source = "git::https://github.com/iamwonodi/terraform-aws-documentdb.git?ref=v1.0.1"

  project_name = "acme"
  environment  = "staging"

  master_username = "platformadmin"
  master_password = random_password.documentdb.result

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

One `db.t4g.medium` instance named `acme-staging-docdb-1`, encrypted, deletion-protected, reachable only from the application's security group.

## Production, highly available

```hcl
module "documentdb" {
  source = "git::https://github.com/iamwonodi/terraform-aws-documentdb.git?ref=v1.0.1"

  project_name = "acme"
  environment  = "production"
  name         = "mongodb"

  engine_version = "5.0.0"

  master_username = "platformadmin"
  master_password = random_password.documentdb.result

  instance_count = 2
  instance_class = "db.r6g.large"

  backup_retention_period = 14
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  cluster_parameters = {
    audit_logs = { value = "enabled" }
  }
  enabled_cloudwatch_logs_exports = ["audit"]
}
```

## Serverless

```hcl
module "documentdb" {
  source = "git::https://github.com/iamwonodi/terraform-aws-documentdb.git?ref=v1.0.1"

  project_name = "acme"
  environment  = "production"

  engine_version = "5.0.0"

  master_username = "platformadmin"
  master_password = random_password.documentdb.result

  instance_count = 2
  serverless     = { min_capacity = 0.5, max_capacity = 8 }

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

## Bringing your own security group

```hcl
  create_security_group = false
  security_group_ids    = [aws_security_group.documentdb.id]
```

The rules then belong on your group; `allowed_security_group_ids` and `allowed_cidr_blocks` are refused, since they describe rules on the group this module would have created.

---

# The administrator credential

The module takes `master_username` and `master_password` and does nothing else with them: it neither generates nor stores the credential. Generate it and keep it with the project's other secrets (see `examples/complete`).

DocumentDB's rules differ from RDS's:

* **User name:** 1 to 63 **letters or digits**, beginning with a letter. No underscores, so `platform_admin` is refused; use `platformadmin`.
* **Password:** 8 to 100 characters, without `/`, `"`, `@` (or a space).

`manage_master_user_password` is deliberately not used: it would create a secret this module does not control.

---

# Connecting

Applications connect to **`endpoint`**, which always points at the writer. `reader_endpoint` spreads reads across the readers, for reads that tolerate slight replication lag.

**TLS is on** (AWS's default parameter group sets `tls = enabled`), so clients need the Amazon RDS certificate bundle. DocumentDB does not support MongoDB's retryable writes; drivers connecting to it should set `retryWrites=false`.

---

# Deletion protection and the final snapshot

`deletion_protection = true` and `skip_final_snapshot = false` by default. Destroying the cluster therefore takes two steps (turn protection off, apply, then destroy), and leaves a snapshot named `<identifier>-final-<timestamp>`. The timestamp keeps a destroy-recreate-destroy from colliding with the first snapshot; the name is ignored in plans so it does not show a change every time.

---

# Parameters and logs

With `cluster_parameters` empty the cluster uses AWS's default parameter group. Setting any parameter creates the cluster's own group, whose family comes from `engine_version` (`5.0.0` gives `docdb5.0`), so `engine_version` must be set. Parameters apply at the next reboot unless `apply_method = "immediate"`.

A log export needs its parameter too: `audit` needs `audit_logs = enabled`, `profiler` needs `profiler = enabled`. CloudWatch bills for what it stores.

---

# Validation

Refused at plan time, before AWS sees them:

* a `master_username` with anything but letters and digits, and a `master_password` outside 8 to 100 characters or containing `/`, `"`, `@` or a space;
* `instance_count` outside 1 to 16;
* serverless capacities outside 0.5 to 256, off the 0.5 step, or with the minimum above the maximum;
* serverless on an engine version before 5.0.0;
* `cluster_parameters` without `engine_version`, or together with `parameter_group_name`;
* a `backup_retention_period` outside 1 to 35;
* log exports other than `audit` and `profiler`;
* no security group at all, or rules for a security group the module is not creating.

---

# Inputs

## Required

| Name | Type | Description |
| --- | --- | --- |
| `project_name` | `string` | Project the cluster belongs to |
| `environment` | `string` | Environment the cluster belongs to |
| `master_username` | `string` | Administrator user name (letters and digits) |
| `master_password` | `string` (sensitive) | Administrator password |
| `vpc_id` | `string` | VPC for the security group |
| `subnet_ids` | `list(string)` | At least two subnets, in different zones |

## Naming

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | `string` | `null` (`docdb`) | Distinguishes this cluster in the environment |
| `identifier` | `string` | `null` | Overrides `<project>-<environment>-<name>`; at most 60 characters |

## Engine

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `engine_version` | `string` | `null` | For example `5.0.0`; null lets AWS choose |
| `allow_major_version_upgrade` | `bool` | `false` | Permit a major version change |
| `auto_minor_version_upgrade` | `bool` | `true` | Minor upgrades in the maintenance window |
| `port` | `number` | `27017` | Port the cluster accepts connections on |
| `cluster_parameters` | `map(object)` | `{}` | Parameters; non-empty creates a group |
| `parameter_group_name` | `string` | `null` | An existing group instead |

## Capacity

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_count` | `number` | `1` | Instances, 1 to 16; 2 or more for high availability |
| `instance_class` | `string` | `db.t4g.medium` | Provisioned class; ignored when serverless |
| `serverless` | `object` | `null` | `{ min_capacity, max_capacity }` in DCUs |

## Storage and encryption

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `storage_type` | `string` | `standard` | `standard` or `iopt1` |
| `storage_encrypted` | `bool` | `true` | Encrypt storage, backups and snapshots |
| `kms_key_id` | `string` | `null` | Customer-managed key; null uses AWS's |

## Backups, maintenance and deletion

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `backup_retention_period` | `number` | `7` | Days, 1 to 35 |
| `backup_window` | `string` | `null` | `hh24:mi-hh24:mi`, UTC |
| `maintenance_window` | `string` | `null` | `ddd:hh24:mi-ddd:hh24:mi`, UTC |
| `deletion_protection` | `bool` | `true` | Refuse deletion |
| `skip_final_snapshot` | `bool` | `false` | Delete without a final snapshot |
| `final_snapshot_identifier` | `string` | `null` | Name of the final snapshot |
| `apply_immediately` | `bool` | `false` | Apply changes now, not in the window |

## Network

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `create_security_group` | `bool` | `true` | Create the cluster's security group |
| `security_group_ids` | `list(string)` | `[]` | Existing groups to attach as well |
| `allowed_security_group_ids` | `list(string)` | `[]` | Groups allowed to reach the port |
| `allowed_cidr_blocks` | `list(string)` | `[]` | IPv4 CIDRs allowed to reach the port |
| `ca_cert_identifier` | `string` | `null` | Certificate authority for the instances |

## Observability

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled_cloudwatch_logs_exports` | `list(string)` | `[]` | `audit`, `profiler` |
| `performance_insights_enabled` | `bool` | `false` | Performance Insights on each instance |
| `tags` | `map(string)` | `{}` | Tags for every resource |

---

# Outputs

| Name | Description |
| --- | --- |
| `id` | The cluster's identifier |
| `arn` | ARN of the cluster |
| `cluster_resource_id` | Immutable resource ID |
| `engine_version` | The engine version running |
| `endpoint` | Writer endpoint; applications connect here |
| `reader_endpoint` | Reader endpoint |
| `port` | Port |
| `master_username` | Administrator user name |
| `instance_ids` | Instance identifiers, writer first |
| `instance_endpoints` | Each instance's own endpoint |
| `instance_availability_zones` | Each instance's zone, writer first |
| `instance_class` | The instances' class (`db.serverless` when serverless) |
| `security_group_id` | The group this module created, or null |
| `security_group_ids` | Every group attached |
| `subnet_group_name` | The subnet group |
| `parameter_group_name` | The parameter group, or null for AWS's default |

---

# Security Considerations

* The cluster is never public: DocumentDB has no public endpoint, and the security group admits only the groups or CIDRs named.
* TLS is enforced by AWS's default parameter group. Setting `tls = disabled` through `cluster_parameters` is possible and should not be done outside a test.
* Storage is encrypted by default, and cannot be encrypted after creation.
* The administrator credential stays with the caller.
* Prefer `allowed_security_group_ids` to CIDRs: a security group follows its instances as they change.

---

# Module Structure

```text
terraform-aws-documentdb/
├── .gitignore
├── .terraform.lock.hcl
├── README.md
├── versions.tf
├── variables.tf
├── locals.tf
├── data.tf          -- the subnets, for their availability zones
├── main.tf
├── outputs.tf
├── tests/
│   └── documentdb.tftest.hcl
└── examples/
    └── complete/
        ├── .terraform.lock.hcl
        ├── version.tf
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

Run the tests with `terraform init -backend=false && terraform test`. They mock the provider, so they need no AWS access.

---

# Versioning

This module follows Semantic Versioning. Consume it by tag, never by branch.

Current release:

```text
v1.0.1
```

`v1.0.1` is a **patch** release relative to `v1.0.0`. It fixes the first plan of a fresh environment: the security-group ingress rules (`aws_vpc_security_group_ingress_rule.from_security_group`) were keyed by the IDs passed in, which are unknown until apply when those resources are created in the same run, so the plan failed with `Invalid for_each argument`. They are now keyed by position in the list. No input or output changed; listing the same ID twice is now refused rather than silently merged.

**Upgrading an environment already applied with `v1.0.0`:** the plan re-creates those resources once under their new keys. To keep them in place, add a `moved` block per entry in the calling configuration, for example `moved { from = module.<name>.<resource>["<id>"]  to = module.<name>.<resource>["0"] }`. Keep the list's order stable afterwards: reordering it re-creates the moved entries.


---

# License

This module is provided for reusable AWS infrastructure deployments and is intended to be consumed as a versioned Terraform module.
