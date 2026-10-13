output "dokploy_dashboard" {
  value = var.close_admin_ports ? "The panel is closed to the internet: open a Bastion port forwarding session to port 3000 (see bastion_session_commands), then browse to http://localhost:3000/ (wait 3-5 minutes to finish Dokploy installation)" : "http://${var.use_reserved_public_ip ? oci_core_public_ip.main[0].ip_address : oci_core_instance.dokploy_main.public_ip}:3000/ (wait 3-5 minutes to finish Dokploy installation)"
}

# Dokploy reaches the workers over SSH from inside the VCN, and the security list only accepts that
# traffic from the VCN, so the server is added in the dashboard with its private IP.
output "dokploy_worker_ips" {
  value = [
    for i, instance in oci_core_instance.dokploy_worker :
    "${instance.private_ip} (private IP: use it to add the server in Dokploy Dashboard; public IP for your own SSH: ${var.use_reserved_public_ip ? oci_core_public_ip.worker[i].ip_address : instance.public_ip})"
  ]
}

# One command per port (the panel and SSH). Needs ~/.ssh/bastion_session.pub, see the README.
output "bastion_session_commands" {
  value = var.enable_bastion ? [
    for port in [3000, 22] :
    "oci bastion session create-port-forwarding --bastion-id ${oci_bastion_bastion.dokploy[0].id} --ssh-public-key-file ~/.ssh/bastion_session.pub --target-private-ip ${oci_core_instance.dokploy_main.private_ip} --target-port ${port} --session-ttl 10800 --display-name dokploy-${port} --wait-for-state SUCCEEDED"
  ] : null
}
