# Oracle Always Free limits for the Arm A1 shape and for volumes (docs.oracle.com, Always Free Resources).
# They are totals for the whole tenancy, so the main node and every worker share them.
# These numbers are repeated by hand in variables.tf (validations), in the error messages of
# main.tf and in the README, because a variable validation cannot read a local in Terraform 1.5:
# change all of them together if Oracle changes the limits.
locals {
  always_free = {
    max_ocpus          = 2
    max_memory_gbs     = 12
    max_boot_total_gbs = 200
    min_boot_size_gbs  = 50 # Used when the disk size is left empty (the image default is 47 GB)
  }
}

# Instance config
locals {
  instance_config = {
    is_pv_encryption_in_transit_enabled = true
    ssh_authorized_keys                 = var.ssh_authorized_keys
    shape                               = var.instance_shape
    shape_config = {
      memory_in_gbs = var.memory_in_gbs
      ocpus         = var.ocpus
    }
    source_details = {
      source_id               = var.source_image_id
      source_type             = "image"
      boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
    }
    availability_config = {
      recovery_action = "RESTORE_INSTANCE"
    }
    instance_options = {
      are_legacy_imds_endpoints_disabled = false
    }
  }
}
