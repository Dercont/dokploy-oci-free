# Weekly backup of the main instance's boot volume.
# Free Tier includes 5 volume backups in total, so a custom policy with a single weekly
# incremental schedule and a short retention is used. Oracle's predefined policies
# (bronze, silver, gold) keep more backups than that.
resource "oci_core_volume_backup_policy" "dokploy_weekly" {
  count          = var.enable_weekly_backup ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "dokploy-weekly-${random_string.resource_code.result}"

  schedules {
    backup_type       = "INCREMENTAL"
    period            = "ONE_WEEK"
    offset_type       = "STRUCTURED"
    offset_seconds    = 0 # As in Oracle's own example for STRUCTURED schedules
    day_of_week       = var.backup_day_of_week
    hour_of_day       = var.backup_hour_utc
    time_zone         = "UTC"
    retention_seconds = var.backup_retention_weeks * 7 * 24 * 60 * 60
  }
}

# A volume can only have one backup policy assigned
resource "oci_core_volume_backup_policy_assignment" "dokploy_main_boot_volume" {
  count     = var.enable_weekly_backup ? 1 : 0
  asset_id  = oci_core_instance.dokploy_main.boot_volume_id
  policy_id = oci_core_volume_backup_policy.dokploy_weekly[0].id
}
