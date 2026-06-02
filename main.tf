data "oci_identity_availability_domains" "this" {
  compartment_id = coalesce(var.tenancy_ocid, var.compartment_ocid)
}

data "oci_core_images" "this" {
  count                    = var.source_image_id == null ? 1 : 0
  compartment_id           = var.compartment_ocid
  operating_system         = var.operating_system
  operating_system_version = var.operating_system_version
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  availability_domain = coalesce(
    var.availability_domain,
    data.oci_identity_availability_domains.this.availability_domains[0].name
  )

  image_id = coalesce(
    var.source_image_id,
    data.oci_core_images.this[0].images[0].id
  )

  is_flexible_shape = can(regex("\\.Flex$", var.shape))

  merged_metadata = merge(
    length(var.ssh_authorized_keys) > 0 ? {
      ssh_authorized_keys = join("\n", var.ssh_authorized_keys)
    } : {},
    var.user_data != null ? {
      user_data = var.user_data
    } : {},
    var.metadata
  )

  pool_size = var.enable_autoscale ? var.autoscaling_initial_instances : var.instance_pool_size

  placement_configurations = length(var.placement_configurations) > 0 ? var.placement_configurations : [
    {
      availability_domain = local.availability_domain
      primary_subnet_id   = var.subnet_id
      fault_domains       = []
    }
  ]
}

resource "oci_core_instance" "this" {
  count               = var.deployment_mode == "instance" ? 1 : 0
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = coalesce(var.display_name, var.name)
  fault_domain        = var.fault_domain
  shape               = var.shape

  dynamic "shape_config" {
    for_each = local.is_flexible_shape ? [1] : []

    content {
      ocpus         = var.shape_config.ocpus
      memory_in_gbs = var.shape_config.memory_in_gbs
    }
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.assign_public_ip
    hostname_label   = var.hostname_label
    display_name     = "${var.name}-primary-vnic"
    nsg_ids          = var.nsg_ids
    private_ip       = var.private_ip
  }

  metadata          = local.merged_metadata
  extended_metadata = var.extended_metadata

  dynamic "agent_config" {
    for_each = var.agent_config == null ? [] : [var.agent_config]

    content {
      are_all_plugins_disabled = try(agent_config.value.are_all_plugins_disabled, null)
      is_management_disabled   = try(agent_config.value.is_management_disabled, null)
      is_monitoring_disabled   = try(agent_config.value.is_monitoring_disabled, null)

      dynamic "plugins_config" {
        for_each = try(agent_config.value.plugins_config, [])

        content {
          desired_state = plugins_config.value.desired_state
          name          = plugins_config.value.name
        }
      }
    }
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    precondition {
      condition     = !local.is_flexible_shape || var.shape_config != null
      error_message = "shape_config must be set when using a Flex shape."
    }
  }
}

resource "oci_load_balancer_backend" "instance" {
  count = var.deployment_mode == "instance" && var.lb_attachment != null ? 1 : 0

  load_balancer_id = var.lb_attachment.load_balancer_id
  backendset_name  = var.lb_attachment.backendset_name
  ip_address       = oci_core_instance.this[0].private_ip
  port             = var.lb_attachment.port
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

data "oci_core_vnic_attachments" "instance" {
  count = var.deployment_mode == "instance" ? 1 : 0

  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.this[0].id

  depends_on = [oci_core_instance.this]
}

data "oci_core_vnic" "instance_primary" {
  count = var.deployment_mode == "instance" ? 1 : 0

  vnic_id = data.oci_core_vnic_attachments.instance[0].vnic_attachments[0].vnic_id
}

data "oci_core_private_ips" "instance_primary" {
  count = var.deployment_mode == "instance" ? 1 : 0

  subnet_id = var.subnet_id
  vnic_id   = data.oci_core_vnic.instance_primary[0].id
}

resource "oci_core_instance_configuration" "this" {
  count          = var.deployment_mode == "instance_pool" ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = "${var.name}-instance-configuration"

  instance_details {
    instance_type = "compute"

    launch_details {
      availability_domain = local.availability_domain
      compartment_id      = var.compartment_ocid
      display_name        = coalesce(var.display_name, var.name)
      shape               = var.shape

      dynamic "shape_config" {
        for_each = local.is_flexible_shape ? [1] : []

        content {
          ocpus         = var.shape_config.ocpus
          memory_in_gbs = var.shape_config.memory_in_gbs
        }
      }

      create_vnic_details {
        subnet_id        = var.subnet_id
        assign_public_ip = var.assign_public_ip
        hostname_label   = var.hostname_label
        display_name     = "${var.name}-primary-vnic"
        nsg_ids          = var.nsg_ids
      }

      metadata          = local.merged_metadata
      extended_metadata = var.extended_metadata

      dynamic "agent_config" {
        for_each = var.agent_config == null ? [] : [var.agent_config]

        content {
          are_all_plugins_disabled = try(agent_config.value.are_all_plugins_disabled, null)
          is_management_disabled   = try(agent_config.value.is_management_disabled, null)
          is_monitoring_disabled   = try(agent_config.value.is_monitoring_disabled, null)

          dynamic "plugins_config" {
            for_each = try(agent_config.value.plugins_config, [])

            content {
              desired_state = plugins_config.value.desired_state
              name          = plugins_config.value.name
            }
          }
        }
      }

      source_details {
        source_type             = "image"
        image_id                = local.image_id
        boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
      }
    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !local.is_flexible_shape || var.shape_config != null
      error_message = "shape_config must be set when using a Flex shape."
    }

    precondition {
      condition     = !var.enable_autoscale || var.autoscaling_initial_instances >= var.autoscaling_min_instances
      error_message = "autoscaling_initial_instances must be greater than or equal to autoscaling_min_instances."
    }

    precondition {
      condition     = !var.enable_autoscale || var.autoscaling_max_instances >= var.autoscaling_initial_instances
      error_message = "autoscaling_max_instances must be greater than or equal to autoscaling_initial_instances."
    }

    precondition {
      condition = (
        !var.enable_autoscale ||
        var.autoscaling_policy_type != "scheduled" ||
        (var.scheduled_scale_out != null && var.scheduled_scale_in != null)
      )
      error_message = "scheduled_scale_out and scheduled_scale_in must be set when scheduled autoscaling is enabled."
    }
  }
}

resource "oci_core_instance_pool" "this" {
  count                     = var.deployment_mode == "instance_pool" ? 1 : 0
  compartment_id            = var.compartment_ocid
  display_name              = coalesce(var.display_name, var.name)
  instance_configuration_id = oci_core_instance_configuration.this[0].id
  size                      = local.pool_size

  dynamic "placement_configurations" {
    for_each = local.placement_configurations

    content {
      availability_domain = placement_configurations.value.availability_domain
      primary_subnet_id   = placement_configurations.value.primary_subnet_id
      fault_domains       = placement_configurations.value.fault_domains
    }
  }

  dynamic "load_balancers" {
    for_each = var.lb_attachment == null ? [] : [var.lb_attachment]

    content {
      load_balancer_id = load_balancers.value.load_balancer_id
      backend_set_name = load_balancers.value.backendset_name
      port             = load_balancers.value.port
      vnic_selection   = load_balancers.value.vnic_selection
    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
}

resource "oci_autoscaling_auto_scaling_configuration" "threshold" {
  count = var.deployment_mode == "instance_pool" && var.enable_autoscale && var.autoscaling_policy_type == "threshold" ? 1 : 0

  compartment_id       = var.compartment_ocid
  display_name         = "${var.name}-autoscaling-threshold"
  cool_down_in_seconds = var.autoscaling_cooldown_in_seconds

  auto_scaling_resources {
    id   = oci_core_instance_pool.this[0].id
    type = "instancePool"
  }

  policies {
    display_name = "${var.name}-threshold-policy"
    policy_type  = "threshold"

    capacity {
      min     = tostring(var.autoscaling_min_instances)
      initial = tostring(var.autoscaling_initial_instances)
      max     = tostring(var.autoscaling_max_instances)
    }

    rules {
      display_name = "${var.name}-scale-out"

      action {
        type  = "CHANGE_COUNT_BY"
        value = tostring(var.scale_out_step)
      }

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "GT"
          value    = tostring(var.scale_out_cpu_threshold)
        }
      }
    }

    rules {
      display_name = "${var.name}-scale-in"

      action {
        type  = "CHANGE_COUNT_BY"
        value = tostring(-1 * var.scale_in_step)
      }

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "LT"
          value    = tostring(var.scale_in_cpu_threshold)
        }
      }
    }
  }
}

resource "oci_autoscaling_auto_scaling_configuration" "scheduled" {
  count = var.deployment_mode == "instance_pool" && var.enable_autoscale && var.autoscaling_policy_type == "scheduled" ? 1 : 0

  compartment_id       = var.compartment_ocid
  display_name         = "${var.name}-autoscaling-scheduled"
  cool_down_in_seconds = var.autoscaling_cooldown_in_seconds

  auto_scaling_resources {
    id   = oci_core_instance_pool.this[0].id
    type = "instancePool"
  }

  policies {
    display_name = "${var.name}-scheduled-scale-out"
    policy_type  = "scheduled"

    capacity {
      min     = tostring(var.scheduled_scale_out.min)
      initial = tostring(var.scheduled_scale_out.initial)
      max     = tostring(var.scheduled_scale_out.max)
    }

    execution_schedule {
      expression = var.scheduled_scale_out.expression
      timezone   = var.scheduled_scale_out.timezone
      type       = "cron"
    }
  }

  policies {
    display_name = "${var.name}-scheduled-scale-in"
    policy_type  = "scheduled"

    capacity {
      min     = tostring(var.scheduled_scale_in.min)
      initial = tostring(var.scheduled_scale_in.initial)
      max     = tostring(var.scheduled_scale_in.max)
    }

    execution_schedule {
      expression = var.scheduled_scale_in.expression
      timezone   = var.scheduled_scale_in.timezone
      type       = "cron"
    }
  }
}
