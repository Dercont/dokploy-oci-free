variable "ssh_authorized_keys" {
  description = "SSH public key for instances. For example: ssh-rsa AAEAAAA....3R ssh-key-2024-09-03"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment. Find it: Profile → Tenancy: youruser → Tenancy information → OCID https://cloud.oracle.com/tenancy"
  type        = string
}

variable "source_image_id" {
  description = "Source Ubuntu 22.04 image OCID. It must be an aarch64 platform image (check it with the command in the README, section Check the image). Find the right one for your region: https://docs.oracle.com/en-us/iaas/images/image/128dbc42-65a9-4ed0-a2db-be7aa584c726/index.htm"
  type        = string
}

variable "num_worker_instances" {
  description = "Number of Dokploy worker instances to deploy: 0 or 1. Always Free Arm gives 2 OCPUs and 12 GB in total for the main node and the workers, so with 1 worker each node gets 1 OCPU and 6 GB."
  type        = number
  default     = 1
  nullable    = false # An explicit null falls back to the default, so the limit checks always run

  validation {
    condition     = var.num_worker_instances >= 0 && var.num_worker_instances <= 1 && floor(var.num_worker_instances) == var.num_worker_instances
    error_message = "num_worker_instances must be 0 or 1. Always Free Arm gives 2 OCPUs and 12 GB in total, and every instance needs at least 1 OCPU."
  }
}

variable "availability_domain_main" {
  description = "Availability domain for dokploy-main instance. Find it Core Infrastructure → Compute → Instances → Availability domain (left menu). For example: WBJv:EU-FRANKFURT-1-AD-1"
  type        = string
}

variable "availability_domain_workers" {
  description = "Availability domain for dokploy-worker instances. Find it Core Infrastructure → Compute → Instances → Availability domain (left menu). For example: WBJv:EU-FRANKFURT-1-AD-2"
  type        = string
}

variable "instance_shape" {
  description = "The shape of the instance. Only VM.Standard.A1.Flex is accepted: it is the only Arm shape in Always Free, and any other shape is billed."
  type        = string
  default     = "VM.Standard.A1.Flex" # OCI Free

  validation {
    condition     = var.instance_shape == "VM.Standard.A1.Flex"
    error_message = "instance_shape must be VM.Standard.A1.Flex, the only Arm shape in Always Free. Any other shape is billed."
  }
}

variable "memory_in_gbs" {
  description = "Memory in GBs for each instance (the main node and every worker use the same value). Always Free Arm gives 12 GB in total: 12 GB with no workers, 6 GB with 1 worker. Oracle requires at least 1 GB per OCPU."
  type        = string
  default     = "6" # OCI Free

  # try() because && does not short-circuit: tonumber("abc") would otherwise raise an error instead of a message.
  validation {
    condition     = try(tonumber(var.memory_in_gbs) >= 1 && tonumber(var.memory_in_gbs) <= 12, false)
    error_message = "memory_in_gbs must be a number between 1 and 12. Always Free Arm gives 12 GB in total (main node plus workers)."
  }
}

variable "ocpus" {
  description = "OCPUs for each instance (the main node and every worker use the same value). Always Free Arm gives 2 OCPUs in total: 2 OCPUs with no workers, 1 OCPU with 1 worker."
  type        = string
  default     = "1" # OCI Free

  validation {
    condition     = try(tonumber(var.ocpus) >= 1 && tonumber(var.ocpus) <= 2 && floor(tonumber(var.ocpus)) == tonumber(var.ocpus), false)
    error_message = "ocpus must be a whole number between 1 and 2. Always Free Arm gives 2 OCPUs in total (main node plus workers)."
  }
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume (disk) size in GBs for each instance (50 to 200). Leave empty to keep the image default (47 GB). Always Free gives 200 GB in total for all boot and block volumes: 200 GB with no workers, 100 GB with 1 worker. A disk can be made bigger but never smaller once created."
  type        = number
  default     = null # Image default (47 GB)

  validation {
    condition     = var.boot_volume_size_in_gbs == null ? true : (var.boot_volume_size_in_gbs >= 50 && var.boot_volume_size_in_gbs <= 200 && floor(var.boot_volume_size_in_gbs) == var.boot_volume_size_in_gbs)
    error_message = "boot_volume_size_in_gbs must be empty or a whole number between 50 and 200. Always Free gives 200 GB in total for all boot and block volumes."
  }
}

variable "use_reserved_public_ip" {
  description = "If true, assign reserved (static) public IPs to instances instead of ephemeral. Reserved IPs persist if the instance is recreated."
  type        = bool
  default     = true
  nullable    = false
}

variable "admin_cidr" {
  description = "Public IPv4 or CIDR allowed to reach SSH (22) and the Dokploy panel (3000), e.g. 203.0.113.7/32 for a single IP. No default on purpose. Only IPv4 CIDRs of /16 or longer are accepted, so it can never be open to a large part of the internet. Find your IPv4: curl -4 ifconfig.me"
  type        = string

  # Two checks, so that each one gives its own message. Regular expressions are used because
  # cidrcontains() does not exist in Terraform 1.5, the version Resource Manager uses.
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(1[6-9]|2[0-9]|3[0-2])$", var.admin_cidr)) && try(cidrhost(var.admin_cidr, 0) == split("/", var.admin_cidr)[0], false)
    error_message = "admin_cidr must be an IPv4 CIDR such as 203.0.113.7/32 (a single IP needs the /32), with a prefix of /16 or longer and no host bits set (203.0.113.0/24, not 203.0.113.7/24). IPv6 is not supported."
  }

  validation {
    condition     = !can(regex("^(0|10|127)\\.|^192\\.168\\.|^169\\.254\\.|^172\\.(1[6-9]|2[0-9]|3[01])\\.|^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|^2(2[4-9]|[3-5][0-9])\\.", var.admin_cidr))
    error_message = "admin_cidr must be a public address. Private, loopback, link-local, CGNAT and multicast ranges (0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.168/16 and 224/3) never reach the server as the source of your connection, so they would lock you out. Use your public IPv4: curl -4 ifconfig.me"
  }
}

variable "dokploy_version" {
  description = "Dokploy release to install, as a release tag such as v0.30.8 (latest and canary are not accepted). It only applies to the first boot: changing it later does not update a running server."
  type        = string
  default     = "v0.30.8"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.dokploy_version))
    error_message = "dokploy_version must be a release tag such as v0.30.8."
  }
}

variable "enable_weekly_backup" {
  description = "If true, take a weekly incremental backup of the main instance's boot volume. Free Tier includes 5 volume backups in total."
  type        = bool
  default     = true
  nullable    = false
}

variable "backup_retention_weeks" {
  description = "Weeks to keep each weekly backup (1 to 3). Free Tier includes 5 volume backups in total. With at most 3 weeks there are never more than 4 backups, so a slot always stays free for a manual backup."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.backup_retention_weeks >= 1 && var.backup_retention_weeks <= 3 && floor(var.backup_retention_weeks) == var.backup_retention_weeks
    error_message = "backup_retention_weeks must be a whole number between 1 and 3. Free Tier includes only 5 volume backups in total, and 3 weeks keeps a slot free."
  }
}

variable "backup_day_of_week" {
  description = "Day of the week (UTC) for the weekly backup, in uppercase. For example: SUNDAY"
  type        = string
  default     = "SUNDAY"

  validation {
    condition     = contains(["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"], var.backup_day_of_week)
    error_message = "backup_day_of_week must be a day of the week in uppercase, such as SUNDAY."
  }
}

variable "backup_hour_utc" {
  description = "Hour of the day (0 to 23, UTC) when the weekly backup starts."
  type        = number
  default     = 3

  validation {
    condition     = var.backup_hour_utc >= 0 && var.backup_hour_utc <= 23 && floor(var.backup_hour_utc) == var.backup_hour_utc
    error_message = "backup_hour_utc must be a whole number between 0 and 23."
  }
}

variable "enable_bastion" {
  description = "If true, create an OCI Bastion (free) and allow ports 22 and 3000 from the bastion's private endpoint, next to admin_cidr. Reach them with a Bastion port forwarding session (see the README). Turn it on only after the first deployment works, test a session, and only then set close_admin_ports."
  type        = bool
  default     = false
  nullable    = false
}

variable "close_admin_ports" {
  description = "If true, close ports 22 and 3000 to admin_cidr: the OCI Bastion (enable_bastion = true) is then the only way in. Set it in a second apply, after you have tested a Bastion session; if the session does not work, set it back to false and apply again."
  type        = bool
  default     = false
  nullable    = false
}
