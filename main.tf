# Main instance
resource "oci_core_instance" "dokploy_main" {
  display_name        = "dokploy-main-${random_string.resource_code.result}"
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain_main

  is_pv_encryption_in_transit_enabled = local.instance_config.is_pv_encryption_in_transit_enabled
  shape                               = local.instance_config.shape

  metadata = {
    ssh_authorized_keys = local.instance_config.ssh_authorized_keys
    user_data = base64encode(templatefile("./bin/dokploy-main.sh", {
      dokploy_version = var.dokploy_version
      admin_cidr      = var.admin_cidr
      vcn_cidr        = oci_core_vcn.dokploy_vcn.cidr_block
    }))
  }

  create_vnic_details {
    display_name              = "dokploy-main-${random_string.resource_code.result}"
    subnet_id                 = oci_core_subnet.dokploy_subnet.id
    assign_ipv6ip             = false
    assign_private_dns_record = true
    assign_public_ip          = !var.use_reserved_public_ip

    # With enable_bastion, only the bastion's private endpoint can reach ports 22 and 3000 from
    # inside the subnet (see bastion.tf).
    nsg_ids = var.enable_bastion ? [oci_core_network_security_group.bastion[0].id] : []
  }

  availability_config {
    recovery_action = local.instance_config.availability_config.recovery_action
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = local.instance_config.instance_options.are_legacy_imds_endpoints_disabled
  }

  shape_config {
    memory_in_gbs = local.instance_config.shape_config.memory_in_gbs
    ocpus         = local.instance_config.shape_config.ocpus
  }

  source_details {
    source_id               = local.instance_config.source_details.source_id
    source_type             = local.instance_config.source_details.source_type
    boot_volume_size_in_gbs = local.instance_config.source_details.boot_volume_size_in_gbs
  }

  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  # The cloud-init script only runs on the first boot, so editing it (or dokploy_version) must
  # never replace a server that is already running.
  lifecycle {
    ignore_changes = [metadata["user_data"]]

    # Always Free limits are totals for the main node plus all workers. Terraform 1.5 (the version
    # Resource Manager runs) cannot compare two variables in a variable validation, so the totals
    # are checked here, before anything is created. They only look at the final state, not at the
    # order of the changes: see "Adding or removing a worker" in the README.
    precondition {
      condition     = (1 + var.num_worker_instances) * tonumber(var.ocpus) <= local.always_free.max_ocpus
      error_message = "Over the Always Free Arm limit: (1 + num_worker_instances) x ocpus must be at most 2 OCPUs in total."
    }

    precondition {
      condition     = (1 + var.num_worker_instances) * tonumber(var.memory_in_gbs) <= local.always_free.max_memory_gbs
      error_message = "Over the Always Free Arm limit: (1 + num_worker_instances) x memory_in_gbs must be at most 12 GB in total."
    }

    precondition {
      condition     = (1 + var.num_worker_instances) * coalesce(var.boot_volume_size_in_gbs, local.always_free.min_boot_size_gbs) <= local.always_free.max_boot_total_gbs
      error_message = "Over the Always Free storage limit: (1 + num_worker_instances) x boot_volume_size_in_gbs must be at most 200 GB in total."
    }
  }
}

# Worker instances (similar to main instance)
resource "oci_core_instance" "dokploy_worker" {
  count = var.num_worker_instances

  display_name        = "dokploy-worker-${count.index + 1}-${random_string.resource_code.result}"
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain_workers

  is_pv_encryption_in_transit_enabled = local.instance_config.is_pv_encryption_in_transit_enabled
  shape                               = local.instance_config.shape

  metadata = {
    ssh_authorized_keys = local.instance_config.ssh_authorized_keys
    user_data = base64encode(templatefile("./bin/dokploy-worker.sh", {
      vcn_cidr = oci_core_vcn.dokploy_vcn.cidr_block
    }))
  }

  create_vnic_details {
    display_name              = "dokploy-worker-${count.index + 1}-${random_string.resource_code.result}"
    subnet_id                 = oci_core_subnet.dokploy_subnet.id
    assign_ipv6ip             = false
    assign_private_dns_record = true
    assign_public_ip          = !var.use_reserved_public_ip
  }

  availability_config {
    recovery_action = local.instance_config.availability_config.recovery_action
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = local.instance_config.instance_options.are_legacy_imds_endpoints_disabled
  }

  shape_config {
    memory_in_gbs = local.instance_config.shape_config.memory_in_gbs
    ocpus         = local.instance_config.shape_config.ocpus
  }

  source_details {
    source_id               = local.instance_config.source_details.source_id
    source_type             = local.instance_config.source_details.source_type
    boot_volume_size_in_gbs = local.instance_config.source_details.boot_volume_size_in_gbs
  }

  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  # Create the worker only after the main node is up to date. When the main node is shrunk in the
  # same apply that adds the worker (2 OCPUs and 12 GB down to 1 and 6), the two would otherwise
  # run in parallel and, for a few minutes, the tenancy would hold more than the Always Free limit.
  depends_on = [oci_core_instance.dokploy_main]

  # The cloud-init script only runs on the first boot, so editing it must never replace a worker
  # that is already running.
  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}
