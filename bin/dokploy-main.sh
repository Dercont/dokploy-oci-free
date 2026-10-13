#!/bin/bash
# Cloud-init user data for the main Dokploy node. It runs once, as root, on the first boot.
# Terraform renders it with templatefile(): a dollar sign followed by a brace is a Terraform
# placeholder, so write it with a doubled dollar sign to get a literal one in the shell.
set -eo pipefail

# Add ubuntu user to sudoers
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# SSH: key-only logins and no root login. Dokploy talks to the local Docker socket on this
# node, so it does not need root over SSH here (it only does on remote servers such as the
# workers); only the panel's terminal for the local server defaults to root (see the README).
# The 00- prefix makes sshd read this file before 50-cloud-init.conf, because sshd keeps the
# first value it finds for each setting.
mkdir -p /etc/ssh/sshd_config.d /run/sshd
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
# Check the syntax before reloading so a mistake can never lock us out of the server
if ! sshd -t; then
  rm -f /etc/ssh/sshd_config.d/00-hardening.conf
  echo "sshd rejected the hardening config, it was removed" >&2
  exit 1
fi
# Ubuntu 24.04 starts sshd through ssh.socket: this reloads it if it is running and does
# nothing if it is not, because the next connection then starts it with the new config
systemctl try-reload-or-restart ssh
[ "$(sshd -T | grep -cE '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) no$')" = 3 ] \
  || { echo "SSH hardening is not in effect" >&2; exit 1; }

# With use_reserved_public_ip the instance boots without a public IP and Terraform attaches
# the reserved one afterwards, so wait for the internet before using apt and curl.
timeout 900 sh -c 'until curl -fsS --max-time 5 -o /dev/null https://github.com; do sleep 5; done' \
  || { echo "No internet access after 15 minutes" >&2; exit 1; }

# Install Dokploy ${dokploy_version}. The installer attached to that release is used because
# dokploy.com/install.sh always targets the latest release; DOKPLOY_VERSION pins the image tag.
curl -fsSL "https://github.com/Dokploy/dokploy/releases/download/${dokploy_version}/install.sh" | DOKPLOY_VERSION=${dokploy_version} sh

# No ufw and no host rules for 80, 443 and 3000: Docker publishes them itself and bypasses host
# firewalls (Oracle also advises against ufw on Ubuntu images), so the security list is the
# firewall that matters.
# Docker Swarm traffic from the workers. These rules are always written, even with no workers,
# because this script never runs again and workers can be added later. They only accept the VCN,
# and the security list lets nothing from the VCN reach these ports until a worker exists.
iptables -I INPUT 1 -p tcp -s ${vcn_cidr} --dport 2377 -j ACCEPT
iptables -I INPUT 1 -p udp -s ${vcn_cidr} --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p tcp -s ${vcn_cidr} --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p udp -s ${vcn_cidr} --dport 4789 -j ACCEPT

# Reorder FORWARD chain rules:
# Remove the default REJECT rule (ignore error if not found)
iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true
# Append the REJECT rule at the end so that Docker rules can be matched first
iptables -A FORWARD -j REJECT --reject-with icmp-host-prohibited

netfilter-persistent save

# From here on, the rest of the hardening runs after the rules are saved, so that the rules
# fail2ban adds while running are not saved with them.

# Ban hosts that keep failing SSH logins, but not the administrator, the Docker networks or the VCN.
# The VCN is ignored because the OCI Bastion (enable_bastion) connects from an address of the
# subnet, and every session through it would otherwise share one address that could get banned.
# Port 22 is only reachable from admin_cidr, from the bastion and, with workers, from the VCN.
# ignoreip is written once, here: if admin_cidr changes later it has to be updated by hand (README).
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -o DPkg::Lock::Timeout=300 install -y fail2ban python3-systemd unattended-upgrades
cat > /etc/fail2ban/jail.d/10-sshd.local <<'EOF'
[DEFAULT]
ignoreip = 127.0.0.1/8 172.16.0.0/12 ${vcn_cidr} ${admin_cidr}

[sshd]
enabled  = true
backend  = systemd
mode     = aggressive
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# Install security updates automatically (not other updates, and no automatic reboot).
# Docker is not touched: its packages are on hold and its repository is not an allowed origin.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/52unattended-upgrades-security-only <<'EOF'
#clear Unattended-Upgrade::Allowed-Origins;
Unattended-Upgrade::Allowed-Origins {
        "$${distro_id}:$${distro_codename}-security";
        "$${distro_id}ESMApps:$${distro_codename}-apps-security";
        "$${distro_id}ESM:$${distro_codename}-infra-security";
};
EOF
