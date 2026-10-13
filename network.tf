# VCN configuration
resource "oci_core_vcn" "dokploy_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_id
  display_name   = "network-dokploy-${random_string.resource_code.result}"
  dns_label      = "vcn${random_string.resource_code.result}"
}

# Subnet configuration
resource "oci_core_subnet" "dokploy_subnet" {
  cidr_block     = "10.0.0.0/24"
  compartment_id = var.compartment_id
  display_name   = "subnet-dokploy-${random_string.resource_code.result}"
  dns_label      = "subnet${random_string.resource_code.result}"
  route_table_id = oci_core_vcn.dokploy_vcn.default_route_table_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id

  # Attach the security list
  security_list_ids = [oci_core_security_list.dokploy_security_list.id]
}

# Internet Gateway configuration
resource "oci_core_internet_gateway" "dokploy_internet_gateway" {
  compartment_id = var.compartment_id
  display_name   = "Internet Gateway network-dokploy"
  enabled        = true
  vcn_id         = oci_core_vcn.dokploy_vcn.id
}

# Default Route Table
resource "oci_core_default_route_table" "dokploy_default_route_table" {
  manage_default_resource_id = oci_core_vcn.dokploy_vcn.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.dokploy_internet_gateway.id
  }
}

# Ports used between the Dokploy node and the workers (protocol 6 = TCP, 17 = UDP)
locals {
  node_to_node_ports = [
    { protocol = "6", port = 22, description = "SSH from Dokploy to the workers (VCN only)" },
    { protocol = "6", port = 2377, description = "Docker Swarm cluster management (VCN only)" },
    { protocol = "6", port = 7946, description = "Docker Swarm node communication (VCN only)" },
    { protocol = "17", port = 7946, description = "Docker Swarm node communication UDP (VCN only)" },
    { protocol = "17", port = 4789, description = "Docker Swarm overlay network UDP (VCN only)" },
  ]

  # Administrator access: the Dokploy panel and SSH, only from admin_cidr
  admin_ports = [
    { port = 3000, description = "Dokploy panel (admin only)" },
    { port = 22, description = "SSH (admin only)" },
  ]
}

# Security List for Dokploy
resource "oci_core_security_list" "dokploy_security_list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id
  display_name   = "Dokploy Security List"

  # The panel (3000) and SSH (22) accept only admin_cidr. With close_admin_ports these two rules
  # are removed: the OCI Bastion (enable_bastion, rules in bastion.tf) is then the only way in.
  dynamic "ingress_security_rules" {
    for_each = var.close_admin_ports ? [] : local.admin_ports
    content {
      protocol    = "6" # TCP
      source      = var.admin_cidr
      description = ingress_security_rules.value.description

      tcp_options {
        min = ingress_security_rules.value.port
        max = ingress_security_rules.value.port
      }
    }
  }

  # HTTP & HTTPS traffic
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
    description = "Allow HTTP traffic on port 80"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
    description = "Allow HTTPS traffic on port 443"
  }

  # ICMP traffic
  ingress_security_rules {
    description = "ICMP traffic for 3, 4"
    icmp_options {
      code = "4"
      type = "3"
    }
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = "false"
  }

  ingress_security_rules {
    description = "ICMP traffic for 3"
    icmp_options {
      code = "-1"
      type = "3"
    }
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = "false"
  }

  # Traffic between nodes: SSH from Dokploy to the workers and Docker Swarm. These rules only
  # exist when there are workers and only accept traffic from inside the VCN, never from the internet.
  dynamic "ingress_security_rules" {
    for_each = var.num_worker_instances > 0 ? local.node_to_node_ports : []
    content {
      protocol    = ingress_security_rules.value.protocol
      source      = oci_core_vcn.dokploy_vcn.cidr_block
      description = ingress_security_rules.value.description

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.protocol == "6" ? [ingress_security_rules.value.port] : []
        content {
          min = tcp_options.value
          max = tcp_options.value
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.protocol == "17" ? [ingress_security_rules.value.port] : []
        content {
          min = udp_options.value
          max = udp_options.value
        }
      }
    }
  }

  # Egress Rule (optional, if needed)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress traffic"
  }

  lifecycle {
    # Closing 22 and 3000 without a bastion would leave no way in. Terraform 1.5 cannot compare
    # two variables in a variable validation, so it is checked here.
    precondition {
      condition     = !var.close_admin_ports || var.enable_bastion
      error_message = "close_admin_ports = true needs enable_bastion = true: with ports 22 and 3000 closed and no bastion there would be no way in."
    }
  }
}
