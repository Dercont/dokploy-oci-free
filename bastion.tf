# Optional OCI Bastion (enable_bastion). The service is free for free and paid accounts (Oracle's
# Always Free list: "Bastion is free for both free and paid accounts").
# It sits in the server's own subnet, so its private endpoint reaches the server directly. A port
# forwarding session, opened with the OCI CLI, is the way in. Sessions are not managed here: they
# expire after at most 3 hours and need a new key each time (see the README).
resource "oci_bastion_bastion" "dokploy" {
  count            = var.enable_bastion ? 1 : 0
  bastion_type     = "STANDARD"
  compartment_id   = var.compartment_id
  target_subnet_id = oci_core_subnet.dokploy_subnet.id
  name             = "dokploybastion${random_string.resource_code.result}" # Only letters and digits are accepted

  # Never 0.0.0.0/0: only the administrator's IP can open a session
  client_cidr_block_allow_list = [var.admin_cidr]
  max_session_ttl_in_seconds   = 10800 # 3 hours, the maximum
}

# The bastion reaches the server from its private endpoint. A network security group attached to the
# main node lets that single address (/32) reach ports 3000 and 22, and nothing else in the subnet.
# It is a group and not a security list rule because the subnet already depends on the security
# list, and the endpoint address is only known once the bastion exists: that would be a cycle.
# It is added next to the admin_cidr rules (network.tf); close_admin_ports removes those.
resource "oci_core_network_security_group" "bastion" {
  count          = var.enable_bastion ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id
  display_name   = "bastion-access-${random_string.resource_code.result}"
}

resource "oci_core_network_security_group_security_rule" "bastion" {
  for_each = var.enable_bastion ? { panel = 3000, ssh = 22 } : {}

  network_security_group_id = oci_core_network_security_group.bastion[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "${oci_bastion_bastion.dokploy[0].private_endpoint_ip_address}/32"
  source_type               = "CIDR_BLOCK"
  description               = "OCI Bastion to port ${each.value}"

  tcp_options {
    destination_port_range {
      min = each.value
      max = each.value
    }
  }
}
