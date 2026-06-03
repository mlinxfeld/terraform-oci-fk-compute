# terraform-oci-fk-compute

This repository contains a reusable **Terraform/OpenTofu module** and progressive examples for deploying **Oracle Cloud Infrastructure (OCI) Compute** resources, from regular single instances to **instance pools with autoscaling**.

It is part of the **[FoggyKitchen.com training ecosystem](https://foggykitchen.com/courses-2/)** and is designed to work cleanly with reusable infrastructure modules such as **`terraform-oci-fk-vcn`** and **`terraform-oci-fk-loadbalancer`**.

Support expectations are documented in [SUPPORT.md](SUPPORT.md).

---

## Purpose

The goal of this module is to provide a **clean, composable, and educational reference implementation** for OCI compute:

- Focused on OCI-native compute primitives
- Suitable for both regular single instances and instance pool deployments
- Designed for hands-on learning, module composition, autoscaling scenarios, and multicloud comparisons

This is **not** a full application platform or landing zone. It is a **learning-first, architecture-aware module**.

---

## What the module does

The module creates:

- OCI compute instance
- OCI instance configuration
- OCI instance pool
- Optional threshold-based autoscaling configuration
- Optional scheduled autoscaling configuration
- Optional load balancer attachment for instance pools
- Optional load balancer backend attachment for a single instance

The module intentionally does **not** create:
- VCNs or subnets
- Load Balancers themselves
- Bastion hosts
- Block volumes beyond boot customization
- OS-level software stacks beyond what you choose to inject with cloud-init

Each of those concerns belongs in its own dedicated module.

---

## Repository Structure

```bash
terraform-oci-fk-compute/
├── examples/
│   ├── 01_single_instance/
│   ├── 02_instance_pool_autoscaling/
│   ├── 03_instance_pool_scheduled_autoscaling/
│   ├── 04_instance_pool_with_load_balancer/
│   ├── 05_multiple_instances_with_load_balancer/
│   └── README.md
├── main.tf
├── inputs.tf
├── outputs.tf
├── versions.tf
├── LICENSE
└── README.md
```

All examples are runnable and demonstrate **incremental compute patterns**, starting from a single instance and progressing to autoscaling and load balancer integration.

---

## Example Usage

### Single instance

```hcl
module "compute" {
  source = "git::https://github.com/foggykitchen/terraform-oci-fk-compute.git?ref=v0.2.0"

  name             = "fk-web-01"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  subnet_id        = var.subnet_id

  deployment_mode          = "instance"
  shape                    = "VM.Standard.E4.Flex"
  operating_system_version = "9"
  shape_config = {
    ocpus         = 1
    memory_in_gbs = 8
  }

  ssh_authorized_keys = [file("~/.ssh/id_rsa.pub")]
  assign_public_ip    = false
}
```

### Single instance with Bastion plugin enabled

```hcl
module "compute" {
  source = "git::https://github.com/foggykitchen/terraform-oci-fk-compute.git?ref=v0.2.0"

  name             = "fk-private-vm"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  subnet_id        = var.subnet_id

  deployment_mode          = "instance"
  shape                    = "VM.Standard.E4.Flex"
  operating_system_version = "9"
  shape_config = {
    ocpus         = 1
    memory_in_gbs = 8
  }

  ssh_authorized_keys = [file("~/.ssh/id_rsa.pub")]
  assign_public_ip    = false

  agent_config = {
    is_management_disabled = false
    is_monitoring_disabled = false
    plugins_config = [
      {
        desired_state = "ENABLED"
        name          = "Bastion"
      }
    ]
  }
}
```

### Instance pool with threshold autoscaling

```hcl
module "compute" {
  source = "git::https://github.com/foggykitchen/terraform-oci-fk-compute.git?ref=v0.2.0"

  name             = "fk-web-pool"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  subnet_id        = var.subnet_id

  deployment_mode          = "instance_pool"
  shape                    = "VM.Standard.E4.Flex"
  operating_system_version = "9"
  shape_config = {
    ocpus         = 1
    memory_in_gbs = 8
  }

  enable_autoscale              = true
  autoscaling_policy_type       = "threshold"
  autoscaling_min_instances     = 2
  autoscaling_initial_instances = 2
  autoscaling_max_instances     = 6
  scale_out_cpu_threshold       = 70
  scale_in_cpu_threshold        = 25
}
```

### Instance pool with scheduled autoscaling

```hcl
module "compute" {
  source = "git::https://github.com/foggykitchen/terraform-oci-fk-compute.git?ref=v0.2.0"

  name             = "fk-web-pool-scheduled"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  subnet_id        = var.subnet_id

  deployment_mode          = "instance_pool"
  shape                    = "VM.Standard.E4.Flex"
  operating_system_version = "9"
  shape_config = {
    ocpus         = 1
    memory_in_gbs = 8
  }

  enable_autoscale        = true
  autoscaling_policy_type = "scheduled"

  scheduled_scale_out = {
    expression = "0 0 8 ? * MON-FRI *"
    timezone   = "UTC"
    min        = 2
    initial    = 4
    max        = 6
  }

  scheduled_scale_in = {
    expression = "0 0 20 ? * MON-FRI *"
    timezone   = "UTC"
    min        = 2
    initial    = 2
    max        = 2
  }
}
```

---

## Module Inputs

### Core inputs

| Variable | Type | Required | Description |
|--------|------|----------|-------------|
| `name` | `string` | ✅ | Base display name used for OCI compute resources |
| `compartment_ocid` | `string` | ✅ | OCI compartment OCID |
| `tenancy_ocid` | `string` | ❌ | Optional tenancy OCID used for availability domain discovery |
| `deployment_mode` | `string` | ❌ | `instance` or `instance_pool` |
| `availability_domain` | `string` | ❌ | Optional availability domain override |
| `fault_domain` | `string` | ❌ | Optional fault domain for a single instance |
| `shape` | `string` | ❌ | OCI compute shape |
| `shape_config` | `object` | ❌ | Flexible shape configuration |
| `display_name` | `string` | ❌ | Optional display name override |
| `defined_tags` | `map(string)` | ❌ | Defined tags |
| `freeform_tags` | `map(string)` | ❌ | Freeform tags |

### Image and bootstrap

| Variable | Type | Required | Description |
|--------|------|----------|-------------|
| `source_image_id` | `string` | ❌ | Explicit image OCID |
| `operating_system` | `string` | ❌ | Platform image operating system when `source_image_id` is null |
| `operating_system_version` | `string` | ❌ | Platform image operating system version, `9` by default |
| `boot_volume_size_in_gbs` | `number` | ❌ | Optional boot volume size |
| `ssh_authorized_keys` | `list(string)` | ❌ | SSH public keys injected into metadata |
| `user_data` | `string` | ❌ | Base64-encoded cloud-init or user-data payload |
| `metadata` | `map(string)` | ❌ | Additional instance metadata |
| `extended_metadata` | `map(string)` | ❌ | OCI extended metadata |
| `agent_config` | `object` | ❌ | Optional Oracle Cloud Agent configuration including per-plugin settings |

### Networking

| Variable | Type | Required | Description |
|--------|------|----------|-------------|
| `subnet_id` | `string` | ✅ | Primary subnet OCID |
| `assign_public_ip` | `bool` | ❌ | Assign a public IP to the primary VNIC |
| `private_ip` | `string` | ❌ | Optional static private IP for single-instance mode |
| `hostname_label` | `string` | ❌ | Optional hostname label for the primary VNIC |
| `nsg_ids` | `list(string)` | ❌ | NSG OCIDs applied to the primary VNIC |
| `lb_attachment` | `object` | ❌ | Optional LB attachment used for single instances and instance pools |

### Pool and autoscaling

| Variable | Type | Required | Description |
|--------|------|----------|-------------|
| `instance_pool_size` | `number` | ❌ | Fixed instance pool size when autoscaling is disabled |
| `placement_configurations` | `list(object)` | ❌ | Explicit pool placement definitions |
| `enable_autoscale` | `bool` | ❌ | Enable autoscaling for `instance_pool` |
| `autoscaling_policy_type` | `string` | ❌ | `threshold` or `scheduled` |
| `autoscaling_min_instances` | `number` | ❌ | Minimum autoscaling capacity |
| `autoscaling_initial_instances` | `number` | ❌ | Initial autoscaling capacity |
| `autoscaling_max_instances` | `number` | ❌ | Maximum autoscaling capacity |
| `autoscaling_cooldown_in_seconds` | `number` | ❌ | Cooldown period for autoscaling |
| `scale_out_cpu_threshold` | `number` | ❌ | CPU threshold for scale-out |
| `scale_in_cpu_threshold` | `number` | ❌ | CPU threshold for scale-in |
| `scale_out_step` | `number` | ❌ | Number of instances added on scale-out |
| `scale_in_step` | `number` | ❌ | Number of instances removed on scale-in |
| `scheduled_scale_out` | `object` | ❌ | Scheduled scale-out definition |
| `scheduled_scale_in` | `object` | ❌ | Scheduled scale-in definition |

### Shape config object schema

```hcl
shape_config = object({
  ocpus         = number
  memory_in_gbs = number
})
```

### LB attachment object schema

```hcl
lb_attachment = object({
  load_balancer_id = string
  backendset_name  = string
  port             = number
  vnic_selection   = optional(string, "PrimaryVnic")
})
```

### Scheduled autoscaling object schema

```hcl
scheduled_scale_out = object({
  expression = string
  timezone   = optional(string, "UTC")
  min        = number
  initial    = number
  max        = number
})
```

### Agent config object schema

```hcl
agent_config = object({
  are_all_plugins_disabled = optional(bool)
  is_management_disabled   = optional(bool)
  is_monitoring_disabled   = optional(bool)
  plugins_config = optional(list(object({
    desired_state = string
    name          = string
  })), [])
})
```

---

## Outputs

| Output | Description |
|------|-------------|
| `deployment_mode` | Selected deployment mode |
| `image_id` | Resolved image ID used by the deployment |
| `instance_id` | Single OCI instance OCID |
| `instance_private_ip` | Private IP of the single instance |
| `instance_public_ip` | Public IP of the single instance |
| `primary_vnic_id` | Primary VNIC OCID of the single instance |
| `primary_private_ip_id` | Primary private IP OCID of the single instance |
| `instance_configuration_id` | OCI instance configuration OCID |
| `instance_pool_id` | OCI instance pool OCID |
| `autoscaling_configuration_id` | OCI autoscaling configuration OCID |
| `lb_backend_id` | Backend resource ID created for a single-instance LB attachment |
| `attached_load_balancer` | Echoed load balancer attachment object |

---

## Examples Overview

| Example | Description |
|-------|-------------|
| `01_single_instance` | Single OCI compute instance with Oracle Linux 9 and cloud-init bootstrap |
| `02_instance_pool_autoscaling` | OCI instance pool with threshold autoscaling |
| `03_instance_pool_scheduled_autoscaling` | OCI instance pool with scheduled autoscaling |
| `04_instance_pool_with_load_balancer` | OCI instance pool attached to `terraform-oci-fk-loadbalancer` |
| `05_multiple_instances_with_load_balancer` | Multiple regular OCI instances attached to `terraform-oci-fk-loadbalancer` as static backends |

See [`examples/`](examples) for details.

---

## Design Philosophy

- Explicit over implicit
- Small modules over monoliths
- Compute scaling as infrastructure, not application glue
- Optimized for **learning, reuse, and composition**

This makes the module useful for:
- OCI compute foundations
- instance pool and autoscaling integrations
- load balancer-backed application tiers
- training material
- architecture workshops
- multicloud comparisons (Azure ↔ OCI)

---

## Related Modules & Training

- [terraform-oci-fk-vcn](https://github.com/foggykitchen/terraform-oci-fk-vcn)
- [terraform-oci-fk-loadbalancer](https://github.com/foggykitchen/terraform-oci-fk-loadbalancer)
- [terraform-az-fk-compute](https://github.com/mlinxfeld/terraform-az-fk-compute)

---

## License

Licensed under the **Universal Permissive License (UPL), Version 1.0**.
See [LICENSE](LICENSE) for details.

---

© 2026 [FoggyKitchen.com](https://foggykitchen.com) - Cloud. Code. Clarity.
