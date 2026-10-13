# Dokploy Deployment on OCI Free Tier

This Terraform project deploys a Dokploy instance along with worker nodes in Oracle Cloud Infrastructure (OCI) Free Tier. **Dokploy** is an open-source platform to manage your app deployments and server configurations.

## Deploy

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/Dercont/dokploy-oci-free/archive/refs/heads/security-hardening.zip)

*Clicking the "Deploy to Oracle Cloud" button will load the Oracle Cloud Resource Manager with the ZIP of the `security-hardening` branch of this fork (the hardened version, not the upstream project). During deployment, you'll be prompted to configure the stack parameters: `admin_cidr` is required (see [Security](#security)). Review the settings, **run a plan first and read it**, then apply. With `num_worker_instances = 0` and the default reserved IP and weekly backup, the plan must say 10 to create and 0 to destroy (14 with `enable_bastion`).*

*Terraform version: in Resource Manager, choose Terraform 1.5.x for the stack (1.2.x is the minimum, because the Always Free checks use `precondition` blocks; older versions fail with syntax errors).*

*Working directory: the stack's working directory is the folder that contains the `.tf` files (`main.tf`, `variables.tf`, ...). A GitHub ZIP puts every file inside one top-level folder, `dokploy-oci-free-security-hardening/`: that folder is the working directory, not the ZIP root. Check this setting when you create the stack, and again if you reuse an existing one.*

*The ZIP is built by GitHub from what is pushed to the branch, so push your changes before you use the button. To deploy a local version instead, build a ZIP from committed files only, so that local folders such as `.terraform/` stay out: `git archive --format=zip --prefix=dokploy-oci-free/ -o stack.zip HEAD` (the working directory is then `dokploy-oci-free`).*

## About Dokploy

![Dokploy Logo](doc/dokploy-logo.webp)

Dokploy is an open-source deployment tool designed to simplify the management of servers, applications, and databases on your own infrastructure with minimal setup. It streamlines CI/CD pipelines, ensuring easy and consistent deployments.

For more information, visit the official page at [dokploy.com](https://dokploy.com).

![Dokploy Screenshot](doc/dokploy-screenshot.png)

## OCI Free Tier Overview

Oracle Cloud Infrastructure (OCI) offers a Free Tier with resources ideal for light workloads, such as the VM.Standard.E2.1.Micro instance. These resources are free as long as usage remains within the limits.

For detailed information about the free tier, visit [OCI Free Tier](https://www.oracle.com/cloud/free/).

*Note: Free Tier instances are subject to availability, and you might encounter "Out of Capacity" errors. To bypass this, upgrade to a paid account. This keeps your free-tier benefits but removes the capacity limitations, ensuring access to higher-tier resources if needed. On a paid account anything above Always Free is billed: see [Cost guardrails](#cost-guardrails-pay-as-you-go).*

### Limits the stack enforces

Always Free gives the whole tenancy 2 Arm OCPUs and 12 GB of memory (`VM.Standard.A1.Flex`), 200 GB for boot and block volumes together, and 5 volume backups. The stack refuses anything above that when you plan, before it creates anything: the plan fails with a message that names the setting, and a failed plan must not be applied. The main node and the workers share the totals:

| Setting | Accepted |
| --- | --- |
| `instance_shape` | `VM.Standard.A1.Flex` only (any other shape is billed) |
| `num_worker_instances` | 0 or 1 |
| `ocpus` x (1 + workers) | 1 or 2 each, at most 2 in total |
| `memory_in_gbs` x (1 + workers) | 1 to 12 each, at most 12 GB in total |
| `boot_volume_size_in_gbs` x (1 + workers) | 50 to 200 each, at most 200 GB in total |
| `backup_retention_weeks` | 1 to 3 |

The checks only see what this stack creates. Other A1 instances, volumes or manual backups in the same tenancy count against the same limits. Always Free only applies in the tenancy's home region: deploy the stack there, because the same resources in another region are billed.

## Prerequisites

Before you begin, ensure you have the following:

-   An Oracle Cloud Infrastructure (OCI) account with Free Tier resources available.
-   An SSH public key for accessing the instances.
-   The OCID of an Ubuntu **aarch64 platform image** for your region (see [Check the image](#check-the-image-before-you-apply)).
-   Your public IPv4, to set `admin_cidr`: run `curl -4 ifconfig.me` (the `-4` matters, because a plain request can answer with an IPv6 address, which is not accepted). Some mobile and home providers share one public IPv4 among many customers (CGNAT): then `admin_cidr` also lets in the other customers behind the same address.

### Check the image before you apply

`source_image_id` is free text and the stack does not check it. A wrong image is a cost trap: an x86 image does not run on the Arm shape (the instance fails to create), and an image with a paid licence, such as Red Hat Enterprise Linux or Windows, adds a licence fee per OCPU hour. Before you apply, run:

```
oci compute image get --image-id <OCID>
```

and check that:

-   `operating-system` is `Canonical Ubuntu`.
-   `display-name` contains `aarch64`, for example `Canonical-Ubuntu-22.04-aarch64-2026.09.18-0`. The image has no architecture field, so the name is the only place where it shows.
-   `listing-type` is empty (`null`). A platform image has no listing; any value (for example `COMMUNITY`) means a community or Marketplace image, which can carry a fee.
-   `lifecycle-state` is `AVAILABLE`.

To confirm that it fits the shape, `oci compute image-shape-compatibility-entry list --image-id <OCID> --all` must list `VM.Standard.A1.Flex`.

This is not checked in Terraform on purpose: the provider's image data source has no architecture attribute, a check on the name or on `listing_type` could not be tested offline, and a false alarm would block a valid deployment.

## Servers & Cluster

### Add Servers to Dokploy

To begin deploying applications, you need to add servers to your Dokploy cluster. A server in Dokploy is where your applications will be deployed and managed.

#### Steps to Add Servers:

1.  **Login to Dokploy Dashboard**:
    -   Access the Dokploy dashboard via the main instance's public IP address. You'll need to use the login credentials configured during setup.
1.  **Generate SSH Keys**:
    -   On the left-hand menu, click on "SSH Keys" and add your private and public SSH key to connect your server.
2.  **Navigate to Servers Section**:
    -   On the left-hand menu, click on "Servers" and then "Add Server."
3.  **Fill in Server Details**:
    -   **Server Name**: Give your server a meaningful name.
    -   **IP Address**: For a worker, enter its **private** IP address (`10.0.0.x`, shown by the `dokploy_worker_ips` output). The security list only accepts SSH from the VCN, and a connection to the worker's public IP would arrive from the main instance's public address, which is not allowed.
    -   **SSH Key**: Select the previous created SSH key.
    -   **Username**: The SSH user for connecting to the server, use `root`. Workers accept root login with a key only; the main instance does not accept root login (see [Security](#security)).
4.  **Submit**:
    -   After filling out the necessary fields, click "Submit" to add the server.

### Configure a Dokploy Cluster with new workers

After setting up the main Dokploy instance, you can expand your cluster by adding worker nodes. These worker instances will help distribute the workload for your deployments.

See more info about configuring your cluster on the [Dokploy Cluster Docs](https://docs.dokploy.com/docs/core/cluster).

#### Adding or removing a worker

The Always Free limits are totals for the main node and the workers together (2 OCPUs and 12 GB), and the checks only look at the final state, not at the order of the changes. To stay inside the limits at every moment:

-   **Add a worker**: in a single apply set `num_worker_instances = 1`, `ocpus = 1` and `memory_in_gbs = 6`. The worker is created only after the main node has been resized (it waits for it). Resizing can restart the main node.
-   **Remove a worker**: use two applies, because Terraform cannot order the deletion and the resize. First set `num_worker_instances = 0` and keep `ocpus = 1` and `memory_in_gbs = 6`: the worker is deleted. When it is gone, apply again with `ocpus = 2` and `memory_in_gbs = 12`.
-   **Disks**: a disk can be made bigger but never smaller. If you may add a worker later, keep `boot_volume_size_in_gbs` at 100 or less from the start (the limit is 200 GB in total).

### Updating the server IP in Dokploy (e.g. after switching to reserved IP)

If you change the instance’s public IP (for example from ephemeral to reserved), let Dokploy know about it:

1. In the Dokploy dashboard, go to **Servers**.
2. Click the server whose IP changed.
3. Use **Update server IP** and the “set current public IP” control (double arrows) to set the server’s IP to the new public address. This is for the main server; workers keep their private IP, which does not change.

Note: **Reserved** Static IP does not change unless you release it. It stays in your account until you delete it.

## Security

Only ports 80 and 443 are open to the internet. The panel and SSH only accept your IP (`admin_cidr`). With `enable_bastion` they also accept the OCI Bastion, and with `close_admin_ports` only the bastion (see [OCI Bastion](#oci-bastion-optional)).

| Port | Protocol | Source | Purpose |
| --- | --- | --- | --- |
| 80, 443 | TCP | Internet | Traefik: your apps and the panel domain |
| 3000 | TCP | `admin_cidr` (not with `close_admin_ports`), plus the bastion's private endpoint (one address) with `enable_bastion` | Dokploy panel (plain HTTP) |
| 22 | TCP | `admin_cidr` (not with `close_admin_ports`), plus the bastion's private endpoint (one address) with `enable_bastion` | SSH |
| 22, 2377, 7946, 4789 | TCP/UDP | VCN only, and only if `num_worker_instances` > 0 | SSH from Dokploy to the workers and Docker Swarm |

Ports 81, 444 and 2376 are no longer open: Dokploy does not use them, and 2376 is the Docker API, which must never be exposed. UDP 443 (HTTP/3) is not open either, on purpose: browsers try it first, find nothing and fall back to TCP, which can add a short delay to the first visit. If you ever want it, add an ingress rule for UDP 443 in `network.tf`. Any extra port you publish from Dokploy (for example a database) also needs its own rule there. The ICMP rules (path MTU discovery) are unchanged.

-   **`admin_cidr` is required.** Use your public IPv4 with `/32`, for example `203.0.113.7/32`. It is rejected unless it is an IPv4 CIDR with a prefix of `/16` or longer, with no host bits (`203.0.113.0/24`, not `203.0.113.7/24`) and a public address (not `10.x`, `172.16-31.x`, `192.168.x`, `127.x`, `169.254.x` or `100.64-127.x`, which would lock you out). `0.0.0.0/0` and any other wide range are rejected. If your IP changes you lose the panel and SSH until you update it (see below).
-   **The panel runs on plain HTTP.** Create the admin account as soon as it answers (3 to 5 minutes after the deploy) and enable 2FA or a passkey in Settings > Profile: whoever is admin has root on the server through the Docker socket. To avoid sending the password over HTTP, open an SSH tunnel with `ssh -L 3000:localhost:3000 ubuntu@<IP>` and browse to `http://localhost:3000`. This tunnel has not been tested yet: try it on the first deploy and, if it does not answer, use `ssh -L 3000:10.0.0.x:3000 ubuntu@<IP>` with the private IP of the main instance.
-   **First-boot hardening** (`bin/dokploy-main.sh`): SSH accepts keys only, and root login is off on the main instance. Workers accept root login with a key only because Dokploy connects to them as root. The panel's terminal for the local server (Settings > Web Server > Terminal) also defaults to the user `root`, which the main instance refuses: set the user to `ubuntu` there and run the authorization command as `ubuntu`. Security updates install by themselves, without rebooting: reboot now and then for new kernels. Docker is on hold, so update it by hand.
-   **`fail2ban` is a second layer.** It watches SSH on the main instance and bans a source for 1 hour after 5 failures in 10 minutes (it also counts connections dropped before login, for example an SSH agent that offers many keys). With port 22 limited to `admin_cidr` and the bastion, the only sources that can reach it are you and the bastion, so it is normally idle. It ignores `127.0.0.0/8`, the Docker networks (`172.16.0.0/12`), the VCN (`10.0.0.0/16`, where the OCI Bastion connects from) and the `admin_cidr` you had **at the first boot**: if you change `admin_cidr` later, add the new one by hand (see [Lost access](#lost-access-wrong-or-changed-admin_cidr)).
-   **Host firewall.** There are no host rules for the panel (`ufw` is not used): the security list is the firewall that works, because Docker publishes ports itself and bypasses `ufw` ([Dokploy security guide](https://docs.dokploy.com/docs/core/remote-servers/security)), and Oracle advises against `ufw` on Ubuntu images. The only host rules are the Docker Swarm ports (2377, 7946, 4789), accepted from the VCN only; the main instance writes them even with no workers, so adding workers later needs no manual firewall step (the main node does have to be resized first: see [Adding or removing a worker](#adding-or-removing-a-worker)).
-   **The first-boot scripts run once.** Editing `bin/` or changing `dokploy_version` after the first apply does not touch a running server (`lifecycle.ignore_changes`), so a running server never gets replaced by mistake. Apply such changes by hand, or recreate the server (this deletes its disk).
-   **Pinned version.** `dokploy_version` (default `v0.30.8`) pins the first install. The panel can still offer updates from its own interface.

### Check the first boot

The first-boot script does not report errors to Terraform: a failed step only shows in the log. If the panel does not answer 5 minutes after the deploy, or to confirm the hardening, SSH in and run:

-   `cloud-init status --long`: `done` means the script ended; `error` means it stopped.
-   `sudo tail -n 50 /var/log/cloud-init-output.log`: where it stopped and why. If it stopped before the Dokploy install (for example, no internet after 15 minutes), run the install line of `bin/dokploy-main.sh` by hand; the Dokploy installer itself does not check every step, so also look at the next command.
-   `sudo docker service ls`: `dokploy` and `dokploy-postgres` should show `1/1`, and `sudo docker ps` should list `dokploy-traefik`.
-   `sudo sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin'`: password and keyboard-interactive `no`; root `no` on the main instance and `without-password` (the same as `prohibit-password`) on workers.
-   `systemctl is-active fail2ban` should print `active`, and `apt-config dump | grep Allowed-Origins` should list only the `-security` origins.

### Lost access (wrong or changed `admin_cidr`)

SSH and the panel are blocked by the security list of the VCN, not by the server, so fix the list first:

1.  In Resource Manager, open the stack, then Edit > Edit variables, set `admin_cidr`, Save and Apply. Only the security list changes; the server is not touched. Or, in the console, go to Networking > your VCN > Security Lists > `Dokploy Security List` and edit the rules for ports 22 and 3000 (the next apply overwrites this with `admin_cidr`). With `enable_bastion` the same apply also updates the bastion's allowed list: open a new session after it. If `close_admin_ports` is `true` and the bastion does not work, set it to `false` and apply: ports 22 and 3000 accept `admin_cidr` again.
2.  If the security list already accepts your new IP but SSH is refused or times out after several failed attempts, `fail2ban` may have banned that IP for 1 hour. Wait it out, or unban it from a session that works (another allowed IP, or the serial console in the next step) with `sudo fail2ban-client set sshd unbanip <IP>`. Then add the new IP to the ignore list for good: change `ignoreip` in `/etc/fail2ban/jail.d/10-sshd.local` and run `sudo systemctl restart fail2ban` (`sudo fail2ban-client set sshd addignoreip <IP>` only lasts until the next restart).
3.  If SSH still fails (for example a wrong key), use the serial console: Compute > Instances > your instance > Console connection > Launch Cloud Shell connection. The `ubuntu` user has no password, so reboot into Ubuntu recovery mode to fix `~ubuntu/.ssh/authorized_keys` or `/etc/ssh/sshd_config.d/`. See [Oracle: instance console connections](https://docs.oracle.com/en-us/iaas/Content/Compute/References/serialconsole.htm).

## OCI Bastion (optional)

`enable_bastion` (default `false`) creates an [OCI Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/Concepts/bastionoverview.htm) in the server's subnet. Oracle lists Bastion as free for free and paid accounts. The bastion only accepts sessions from `admin_cidr` (never `0.0.0.0/0`), and a session lasts at most 3 hours. A network security group on the main node lets only the bastion's private endpoint (a single address) reach ports 22 and 3000, so the bastion does not open them to the rest of the subnet. (With workers, the VCN rule for SSH from Dokploy to the workers also reaches port 22 of the main node.)

**This is a second phase, in two applies, so that you can test before you close anything.** Do it only after the first deployment works: the panel answers and you can log in with SSH.

1.  **Open the bastion**: set `enable_bastion = true` and apply. `admin_cidr` keeps working. Open one session for the panel and one for SSH (commands below) and check that both work.
2.  **Close the ports**: only when both sessions work, set `close_admin_ports = true` and apply. Ports 22 and 3000 then stop accepting `admin_cidr` and the internet, and the bastion is the only way in. `close_admin_ports` without `enable_bastion` is rejected by the plan.

-   **If a session does not work**, leave `close_admin_ports` as `false`: nothing was closed. If you already closed the ports, set it back to `false` and apply (the security list changes in place and `admin_cidr` works again). If the bastion itself cannot be created, set `enable_bastion = false` and apply.
-   **Turning the bastion off**: set `close_admin_ports = false` and apply, then `enable_bastion = false` and apply. The group is detached from the server and deleted in the same apply: if Oracle says it is still in use, apply again.
-   **No service gateway.** Oracle's pages do not agree on whether a bastion needs one for port forwarding to a server in a public subnet (one page lists it as a prerequisite, another only for managed SSH sessions), so the stack does not create one. If the bastion cannot be created, that is the first thing to look at. These commands come from Oracle's documentation and have not been run against this stack yet.
-   **GitHub webhooks stop working** once the ports are closed. With port 3000 closed to the internet, GitHub cannot call the panel, so automatic deployments from Git need a domain with HTTPS for the panel (Traefik, port 443). Otherwise deploy by hand from the panel, through the tunnel.

Sessions are not managed by Terraform: they expire after at most 3 hours and Oracle recommends a new key for each one. The `bastion_session_commands` output prints the two commands below with the real values filled in (it names the sessions `dokploy-3000` and `dokploy-22`). A port forwarding session needs no Oracle Cloud Agent plugin on the server.

```
# Once: a key for the sessions (Oracle's tutorial uses RSA 4096; ed25519 is not confirmed)
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/bastion_session

# One session per port: --target-port 3000 for the panel, --target-port 22 for SSH
oci bastion session create-port-forwarding \
  --bastion-id <BASTION_OCID> \
  --ssh-public-key-file ~/.ssh/bastion_session.pub \
  --target-private-ip <SERVER_PRIVATE_IP> \
  --target-port 3000 \
  --session-ttl 10800 \
  --display-name dokploy-3000 \
  --wait-for-state SUCCEEDED

# The tunnel command of a session (it has <privateKey> and <localPort> placeholders to fill in)
oci bastion session get --session-id <SESSION_OCID> --query 'data."ssh-metadata".command' --raw-output
```

Open the tunnels and keep their terminals open, because the command does not end. The two `-o` options are there because, by default, the bastion's SSH server closes an idle connection after 5 minutes:

```
# Panel: then browse to http://localhost:3000
ssh -i ~/.ssh/bastion_session -N -L 3000:<SERVER_PRIVATE_IP>:3000 -p 22 \
  -o ServerAliveInterval=120 -o ServerAliveCountMax=3 \
  <SESSION_OCID>@host.bastion.<REGION>.oci.oraclecloud.com

# SSH, on local port 2222 so it does not clash with a local SSH server; then, in another terminal:
ssh -i ~/.ssh/bastion_session -N -L 2222:<SERVER_PRIVATE_IP>:22 -p 22 \
  -o ServerAliveInterval=120 -o ServerAliveCountMax=3 \
  <SESSION_OCID>@host.bastion.<REGION>.oci.oraclecloud.com
ssh -i ~/.ssh/<your_server_key> -p 2222 ubuntu@localhost
```

If the tunnel connects but the panel does not answer, check on the server that Docker listens on all addresses: `sudo ss -ltnp | grep 3000` (this has not been tested yet). If it says `Permission denied (publickey)` with an RSA key and OpenSSH 8 or later, add `HostKeyAlgorithms +ssh-rsa` and `PubkeyAcceptedKeyTypes +ssh-rsa` to `~/.ssh/config`.

**When your IP changes**, the normal way is to change `admin_cidr` in the stack and apply: that updates the bastion's allowed list too. Then create a new session (the change does not affect sessions that already exist). If you need a quick fix before you can apply, you can update the list from the CLI, but the next apply for any reason puts the list back to `admin_cidr`, so also change `admin_cidr` soon:

```
oci bastion bastion update --bastion-id <BASTION_OCID> --client-cidr-list '["203.0.113.7/32"]'
```

`fail2ban` ignores the whole VCN (`10.0.0.0/16`), which is where the bastion connects from, so sessions through the bastion are not banned. This is written at the first boot: a server created from an older version of this stack does not have it, and then five failed logins through the bastion could ban its address for 1 hour (add the VCN to `ignoreip` by hand; see [Lost access](#lost-access-wrong-or-changed-admin_cidr)). The address the server sees for bastion sessions has not been checked.

## Weekly backup

`backup.tf` takes an incremental backup of the main instance's boot volume once a week, with a custom backup policy (`enable_weekly_backup`, on by default). Free Tier includes only 5 volume backups in total, so Oracle's predefined policies (bronze, silver, gold) are not used: they keep more.

-   **Default schedule**: Sundays at 03:00 UTC, kept for 3 weeks. Change it with `backup_day_of_week`, `backup_hour_utc` and `backup_retention_weeks` (1 to 3).
-   **Free slots**: with at most 3 weeks there are never more than 4 backups, so one of the 5 free slots is always left for a manual backup (for example before an update). That is why 4 weeks is not accepted: up to 5 could exist for a moment and none would be left. On a pay-as-you-go account a 6th backup is billed instead of failing.
-   **After the first apply**: run a second plan in Resource Manager and check that it says "No changes". If it keeps proposing to update the backup policy, the provider and the API disagree on a field of the schedule; the backups still work, but tell whoever maintains the stack.
-   **Backups outlive the server**: they expire on their own, so they still count towards the 5 after a destroy or a recreation of the server.
-   **Limits**: it is a copy of a running disk, not a database dump, so PostgreSQL can be caught mid-write. Restoring creates a new volume instead of replacing the current one. Workers are not backed up.

## Cost guardrails (Pay As You Go)

The checks of the stack only see what the stack creates, and a Pay As You Go account does not stop you at the Always Free limits: Oracle bills anything above them, and the service limits of the account are much higher (the account that was reviewed allowed 250 A1 OCPUs). Two protections are created **apart from the stack, by hand**, in the tenancy:

-   **Compartment quotas** are the only hard stop: Oracle refuses (`QuotaExceeded`) any request above the quota, for example a second A1 instance or a bigger disk. They can take up to 10 minutes to apply.
-   **A budget** only warns, and late: its alerts are evaluated every 24 hours.

**Status of these commands.** Quota object A and the budget below were created on one account on 13/10/2026 and then read back (the values are in the last step of this list), so the statements and the A1 names are accepted by Oracle. Quota object B was **not** created and has not been tested. That the budget alerts fire at 0.01 EUR has not been seen yet. Check each command against Oracle's documentation before you run it. If an object with the same name already exists, `create` fails with a duplicate name: list what you have with `oci limits quota list` first.

Variables used below: `T` is the OCID of the tenancy (it is also the root compartment) and `AD` is the availability domain (the one in `availability_domain_main`).

Quota object A, for compute and disks. Its statements must stay **in the same object and in this order**: if the `zero` lines are in another object, the most restrictive one wins and A1 stays at 0. The two `regional` lines are there because the `zero` statements may also set the regional A1 count to 0, and then the deployment would fail with `QuotaExceeded` (it was not tested without them).

```
zero compute-core quotas in tenancy
set compute-core quota standard-a1-core-count to 2 in tenancy
set compute-core quota standard-a1-core-regional-count to 2 in tenancy
zero compute-memory quotas in tenancy
set compute-memory quota standard-a1-memory-count to 12 in tenancy
set compute-memory quota standard-a1-memory-regional-count to 12 in tenancy
set block-storage quota total-storage-gb to 200 in tenancy
set block-storage quota backup-count to 5 in tenancy
```

Quota object B, other billable services (optional, not tested). It also blocks Object Storage, so Dokploy cannot send backups to OCI Object Storage while it is in place; remove it (or `unset` that line) when you need it. Oracle's documentation says volume backups are stored in Object Storage, and it is not confirmed that this quota leaves them alone: create object B only after the first weekly backup has worked, and check that backups still succeed afterwards.

```
zero load-balancer quotas in tenancy
zero database quotas in tenancy
zero filesystem quotas in tenancy
zero object-storage quota storage-bytes in tenancy
```

Create them:

```
oci limits quota create --compartment-id $T --name always-free-compute-storage --description "Always Free cap: A1 2 OCPU and 12 GB, disks 200 GB, 5 backups" --statements '["zero compute-core quotas in tenancy","set compute-core quota standard-a1-core-count to 2 in tenancy","set compute-core quota standard-a1-core-regional-count to 2 in tenancy","zero compute-memory quotas in tenancy","set compute-memory quota standard-a1-memory-count to 12 in tenancy","set compute-memory quota standard-a1-memory-regional-count to 12 in tenancy","set block-storage quota total-storage-gb to 200 in tenancy","set block-storage quota backup-count to 5 in tenancy"]'

oci limits quota create --compartment-id $T --name always-free-no-other-services --description "No load balancers, databases, File Storage or Object Storage" --statements '["zero load-balancer quotas in tenancy","zero database quotas in tenancy","zero filesystem quotas in tenancy","zero object-storage quota storage-bytes in tenancy"]'
```

A budget of 1 EUR on the whole tenancy, with an alert on real spending at 0.01 and a forecast alert. The first command returns the budget OCID (`BUDGET_ID`) for the other two:

```
oci budgets budget budget create --compartment-id $T --amount 1 --reset-period MONTHLY --display-name always-free-1-eur --description "Any spending means something went outside Always Free" --target-type COMPARTMENT --targets '["<TENANCY_OCID>"]'

oci budgets budget alert-rule create --budget-id $BUDGET_ID --type ACTUAL --threshold 0.01 --threshold-type ABSOLUTE --display-name actual-0-01-eur --recipients "<YOUR_EMAIL>" --message "There is real spending in Oracle Cloud: something went outside Always Free. Check Cost Analysis and stop the resource."

oci budgets budget alert-rule create --budget-id $BUDGET_ID --type FORECAST --threshold 100 --threshold-type PERCENTAGE --display-name forecast-100-percent --recipients "<YOUR_EMAIL>" --message "Oracle forecasts more than 1 EUR this month. Check the consumption."
```

Read-only checks, after waiting 10 minutes. With object A, `effective-quota-value` read back as 2, 12, 2 and 12 (the two `regional` names), 0 (any other shape, here E4), 200 and 5. If a `regional` line shows 0, the deployment would fail with `QuotaExceeded`: fix the quota first.

```
oci limits quota list --compartment-id $T --all
oci limits resource-availability get --service-name compute --limit-name standard-a1-core-count --compartment-id $T --availability-domain $AD
oci limits resource-availability get --service-name compute --limit-name standard-a1-memory-count --compartment-id $T --availability-domain $AD
oci limits resource-availability get --service-name compute --limit-name standard-a1-core-regional-count --compartment-id $T
oci limits resource-availability get --service-name compute --limit-name standard-a1-memory-regional-count --compartment-id $T
oci limits resource-availability get --service-name compute --limit-name standard-e4-core-count --compartment-id $T --availability-domain $AD
oci limits resource-availability get --service-name block-storage --limit-name total-storage-gb --compartment-id $T --availability-domain $AD
oci limits resource-availability get --service-name block-storage --limit-name backup-count --compartment-id $T
oci budgets budget budget list --compartment-id $T --target-type ALL --all
```

### Measure what is billed

Run this 24 hours, 2 days and 4 days after the first apply, after the first Sunday (the first backup) and then once a month. The dates are the first day of this month and tomorrow, at midnight UTC (GNU `date`):

```
oci usage-api usage-summary request-summarized-usages --tenant-id $T --time-usage-started $(date -u +%Y-%m-01T00:00:00Z) --time-usage-ended $(date -u -d tomorrow +%Y-%m-%dT00:00:00Z) --granularity MONTHLY --query-type COST --group-by '["skuPartNumber","skuName","unit"]'
```

Only these five items should appear, all at 0.00: **B91445** (Block Volume - Free), **B93297** (A1 OCPU hours), **B93298** (A1 memory GB hours), **B88327** (outbound data transfer) and **B90926** (Monitoring retrieval). Any other item, such as **B91962** (disk performance units), **B91961**, Cloud Guard, a backup or a public IP, is the defect to look for. If a backup item shows an amount above 0, set `enable_weekly_backup = false` and delete the backups. Also check that `oci cloud-guard configuration get --compartment-id $T` still says `DISABLED`.

## Project Structure

-   `bin/`: Contains bash scripts for setting up Dokploy on both the main instance and the worker instances.
    -   `dokploy-main.sh`: Script to install Dokploy on the main instance.
    -   `dokploy-worker.sh`: Script to configure necessary dependencies on worker instances.
-   `backup.tf`: Weekly backup policy for the main instance's boot volume (see [Weekly backup](#weekly-backup)).
-   `bastion.tf`: Optional OCI Bastion and the network security group that lets it reach ports 22 and 3000, created when `enable_bastion` is `true` (see [OCI Bastion](#oci-bastion-optional)).
-   `helper.tf`: Contains helper functions and reusable modules to streamline the infrastructure setup.
-   `doc/`: Directory for images used in the README (e.g., screenshots of Dokploy setup).
-   `locals.tf`: Defines local values used throughout the Terraform configuration, such as dynamic values or reusable expressions.
-   `main.tf`: Core Terraform configuration file that defines the infrastructure for Dokploy's main and worker instances.
-   `network.tf`: Configuration for setting up the required OCI networking resources (VCNs, subnets, security lists, etc.).
-   `output.tf`: Specifies the output variables such as the IP addresses for the dashboard and worker nodes.
-   `reserved_ips.tf`: Optional reserved (static) public IPs for the main and worker instances when `use_reserved_public_ip` is enabled (see [Reserved public IPs](#updating-the-server-ip-in-dokploy-eg-after-switching-to-reserved-ip)).
-   `providers.tf`: Declares the minimum Terraform version and the Oracle Cloud Infrastructure provider.
-   `README.md`: This file, providing instructions on deployment and usage.
-   `variables.tf`: Defines input variables used in the project, including compartment ID, SSH keys, instance shape, and more.

## Terraform Variables

Below are the key variables for deployment which are defined in `variables.tf`:

-   `ssh_authorized_keys`: Your SSH public key for accessing the instances.
-   `compartment_id`: OCI compartment ID for instance deployment.
-   `num_worker_instances`: Number of worker instances to deploy for Dokploy: 0 or 1 (see [Limits the stack enforces](#limits-the-stack-enforces)).
-   `availability_domain_main`: Availability domain for the main instance.
-   `availability_domain_workers`: Availability domains for worker instances.
-   `instance_shape`: Instance shape (e.g., VM.Standard.A1.Flex) used for deployment.
-   `memory_in_gbs`: Memory size (GB) per instance, applied to the main and worker instances. Always Free gives 12 GB in total: 12 with no workers, 6 with one worker.
-   `ocpus`: Number of OCPUs per instance, applied to the main and worker instances. Always Free gives 2 OCPUs in total: 2 with no workers, 1 with one worker.
-   `boot_volume_size_in_gbs`: Boot volume (VM disk) size in GB per instance, applied to the main and worker instances. Leave it unset to keep the image default (47 GB); when set, the stack accepts 50–200, and the total across all instances must stay within the 200 GB of Always Free (with one worker, at most 100 GB each). Increasing it on an existing deployment resizes the disk in place; reboot the instances so Ubuntu uses the new space.
-   `use_reserved_public_ip`: If `true`, assign reserved (static) public IPs to the main and worker instances instead of ephemeral IPs. Default is `true`. See [Reserved (static) public IPs](#updating-the-server-ip-in-dokploy-eg-after-switching-to-reserved-ip).
-   `admin_cidr`: **Required.** Public IPv4 CIDR allowed to reach SSH and the panel, for example `203.0.113.7/32`. No default; IPv6, private ranges and anything wider than `/16` (including `0.0.0.0/0`) are rejected. See [Security](#security).
-   `dokploy_version`: Dokploy release tag installed on the first boot. Default is `v0.30.8`; `latest` and `canary` are rejected.
-   `enable_weekly_backup`: If `true`, take a weekly backup of the main instance's boot volume. Default is `true`. See [Weekly backup](#weekly-backup).
-   `backup_retention_weeks`: Weeks to keep each backup, from 1 to 3. Default is `3`, which always leaves a free slot of the 5 included.
-   `backup_day_of_week`: Day of the week (UTC) of the backup, in uppercase. Default is `SUNDAY`.
-   `backup_hour_utc`: Hour of the day (0 to 23, UTC) when the backup starts. Default is `3`.
-   `enable_bastion`: If `true`, create an OCI Bastion and let it reach ports 22 and 3000 next to `admin_cidr`; you then reach them through a Bastion port forwarding session. Default is `false`. Turn it on only after the first deployment works. See [OCI Bastion](#oci-bastion-optional).
-   `close_admin_ports`: If `true`, ports 22 and 3000 stop accepting `admin_cidr` and the OCI Bastion is the only way in. Needs `enable_bastion = true`. Default is `false`. Set it in a second apply, after you have tested a Bastion session. See [OCI Bastion](#oci-bastion-optional).
