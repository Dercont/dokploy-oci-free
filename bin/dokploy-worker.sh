#!/bin/bash
# Cloud-init user data for the Dokploy worker nodes. It runs once, as root, on the first boot.
# Terraform renders it with templatefile(): a dollar sign followed by a brace is a Terraform
# placeholder, so write it with a doubled dollar sign to get a literal one in the shell.
set -eo pipefail

# Add ubuntu SSH authorized keys to the root user
# Dokploy connects to the workers over SSH as root (see README), so root keeps its key.
mkdir -p /root/.ssh
cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/
chown root:root /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Add ubuntu user to sudoers
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# SSH: key-only logins. Root can log in with a key (prohibit-password) because Dokploy needs it
# on remote servers, but never with a password. The 00- prefix makes sshd read this file before
# 50-cloud-init.conf, because sshd keeps the first value it finds for each setting.
mkdir -p /etc/ssh/sshd_config.d /run/sshd
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
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
[ "$(sshd -T | grep -cE '^(passwordauthentication|kbdinteractiveauthentication) no$|^permitrootlogin (prohibit|without)-password$')" = 3 ] \
  || { echo "SSH hardening is not in effect" >&2; exit 1; }

# Docker Swarm traffic from the other nodes. The security list also limits these ports to the
# VCN. No ufw: Docker bypasses it and Oracle advises against it on Ubuntu images.
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
