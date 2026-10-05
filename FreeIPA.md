# FreeIPA

## Overview Architecture

This guide sets up central identity management (FreeIPA), home directory sharing (NFS Automount), and dynamic compute node provisioning (xCAT).

- **Management Node (MN):** `xcatmn.cluster.com` (`10.10.10.1` )
- **Compute Nodes (CN):** Dynamically provisioned clients (e.g., `cn1.cluster.com`, `cn2.cluster.com`)
- **Domain / Realm:** `cluster.com` / `CLUSTER.COM`

---

## Phase 0: System Backup Prerequisite

> 🚨 **Critical Safety Check:** Perform a Timeshift snapshot (or VM checkpoint) **after** completing xCAT network/OS setup and **before** starting FreeIPA installation. If FreeIPA installation fails during initial LDAP initialization, restoring from a clean snapshot is significantly faster than manually purging LDAP databases.
> 

# Phase 1: xCAT Pre-Provisioning Scripts

Before deploying FreeIPA, configure xCAT so compute nodes automatically resolve their FQDN during first boot.

### 1. Create Hostname Resolution Script

This script grabs the NODE envvar assigned by xcat for each node during installation containing node hostname and updates `systemd-hostnamed`.

### 1. Create a custom postscript:

```jsx
nano /install/postscripts/setup-hostnames.sh
```

#### and put the following in it:

```jsx
#!/bin/bash
hostnamectl set-hostname "$NODE"
```

#### 2. Make it executable:

```jsx
chmod +x /install/postscripts/set-fqdn-hostname.sh
```

### 2. Assign Postscript to Compute Nodes

Assign the script to your compute node group so it runs automatically upon provisioning completion:

```jsx
chdef cn1 -p postscripts="set-fqdn-hostname.sh"
```

# Phase 2: Management Node (MN) Setup

### Step 1: Install & Configure FreeIPA Server

#### A. Enable IDM Module Stream

Enable the official Red Hat / Rocky Linux Identity Management stream (`DL1` stream):

```bash
dnf module reset idm -y
dnf module enable idm:DL1 -y
dnf install freeipa-server freeipa-server-dns
```

<aside>
💡

`idm`  

👉 *“This is the modular package stream that delivers FreeIPA and its dependencies.”*

---

By enabling `idm:DL1`, you’re saying:

👉 *“Use the supported Identity Management (FreeIPA) version for this OS release.”*

</aside>

#### B. Execute Interactive FreeIPA Setup

Run the installation wizard. Ensure you set matching passwords for directory administration: (the used passwords are rootroot)

```bash
ipa-server-install
#ipa-dns-install
```

- **Domain Name:** `cluster.com`
- **Realm Name:** `CLUSTER.COM`
- **Server Hostname:** `xcatmn.cluster.com`

#### C. Configure System DNS Resolver

Point the management node to its local DNS server:

```bash
echo "nameserver 10.10.10.1" > /etc/resolv.conf
```

#### D. Authenticate via Kerberos

Verify identity management operational status by obtaining an admin Kerberos Ticket-Granting Ticket (TGT):

```bash
	kinit admin
```

<aside>
⚠️

you must enter same password that you set before during configuration

</aside>

<aside>
💡

**What is `kinit`?** `kinit` authenticates your user identity against the Kerberos Key Distribution Center (KDC) and retrieves an encrypted TGT ticket. This token grants administrative rights across LDAP, SSH, and automount services without requiring repeated password prompts.

</aside>

<aside>
💡

to show all commands that can you  use it 

```bash
man ipa
ipa help topics   # to get a list of help topics
ipa help {topic}  # to print help for chosen topic
```

</aside>

### Step 2: Configure NFS Server for Shared Home Directories

NFS hosts the raw disk storage for user home folders. Automount will dynamically expose these shares to compute nodes when users log in.

1. Install NFS utilities

```bash
dnf install nfs-utils -y
```

1. Export /home to cluster network

```bash
echo "/home 10.10.10.0/24(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
```

1. Enable and start NFS service

```bash
systemctl enable --now nfs-server
exportfs -ra
```

### Step 3: Configure Central Automount Maps in FreeIPA

Instead of hardcoding mount entries in `/etc/fstab` on every compute node, FreeIPA stores mount configurations centrally in LDAP. Compute nodes download these maps dynamically on startup.

1. Ensure Kerberos ticket is active

```bash
kinit admin
```

1. Add auto.home map and link it to auto.master

```bash
# 1. Create the auto.home map
ipa automountmap-add default auto.home
# 2. Link /home to auto.home inside auto.master
ipa automountkey-add default auto.master --key=/home --info=auto.home
# 3. Add wildcard key mapping for dynamic user directory mounting
# The '*' matches any username, and '&' substitutes the logged-in username into the path
ipa automountkey-add default auto.home --key="*" --info="xcatmn.cluster.com:/home/&"
```

1. Enable automatic home directory creation on local login

```bash
authselect enable-feature with-mkhomedir
systemctl restart sssd
```

> users need to create their home directory on the master node first though
> 

---

# Phase 3: Compute Node (CN) Postscript Setup

To ensure compute nodes automatically join FreeIPA and configure Automount during image installation, build a single postscript (`freeipa.sh`).

### Step 1: Create the Postscript File

Create `/install/postscripts/freeipa.sh`:

- old
    
    ```bash
    #!/bin/bash
    dnf install -y vim nano htop tmux
    
    ### --- Check & Install nfs-utils --- ###
    if dnf list installed nfs-utils &>/dev/null; then
        echo "[OK] nfs-utils is already installed. Skipping."
    else
        echo "[INFO] Installing nfs-utils..."
        dnf install -y nfs-utils
    
        if dnf list installed nfs-utils &>/dev/null; then
            echo "[SUCCESS] nfs-utils installed successfully."
    
        else
            echo "[ERROR] Failed to install nfs-utils."
            exit 1
        fi
    fi
    
    ### --- Check & Install freeipa-client --- ###
    if which ipa-client-install &>/dev/null; then
        echo "[OK] freeipa-client is already installed. Skipping."
    else
        echo "[INFO] Installing freeipa-client..."
        dnf install -y freeipa-client
    
        if which ipa-client-install &>/dev/null; then
            echo "[SUCCESS] freeipa-client installed successfully."
    
            # Run IPA setup commands only if package was newly installed
            echo "[INFO] Running ipa-client-install..."
            ipa-client-install \
            --unattended \
            --domain=cluster.com \
            --realm=CLUSTER.COM \
            --server=xcatmn.cluster.com \
            --hostname=cn1.cluster.com \
            --principal=admin \
            --password='rootroot' \
            --mkhomedir \
            --force-join \
            --force-ntpd
    
            echo "[INFO] Running ipa-client-automount..."
            ipa-client-automount --unattended --location=default
    	automount -m
        else
            echo "[ERROR] Failed to install freeipa-client."
            exit 1
        fi
    fi
    
    ```
    

```bash
#!/bin/bash
set -eux
### --- Check & Install nfs-utils --- ###
if ! dnf list installed nfs-utils &>/dev/null; then
    echo "[INFO] Installing nfs-utils..."
    dnf install -y nfs-utils
fi

### --- Check & Install freeipa-client --- ###
if which ipa-client-install &>/dev/null; then
    echo "[OK] freeipa-client is already installed. Skipping."
else
    echo "[INFO] Installing freeipa-client..."
    dnf install -y freeipa-client

    # Dynamically fetch FQDN of the local compute node
    NODE_FQDN=$(hostname -f)

    echo "[INFO] Running ipa-client-install..."
    ipa-client-install \
        --unattended \
        --domain=cluster.com \
        --realm=CLUSTER.COM \
        --server=xcatmn.cluster.com \
        --hostname="$NODE_FQDN" \
        --principal=admin \
        --password='rootroot' \
        --mkhomedir \
        --force-join \
        --force-ntpd

    echo "[INFO] Configuring FreeIPA Automount..."
    ipa-client-automount --unattended --location=default
    
    # Enable mkhomedir feature on client
    authselect enable-feature with-mkhomedir
    systemctl restart sssd autofs
fi
```

```bash
#!/bin/bash
set -eux

echo "[INFO] --- Starting Compute Node Provisioning Postscript ---"

### --- 1. Install Required Packages --- ###
echo "[INFO] Installing prerequisite packages..."
dnf install -y nfs-utils autofs chrony freeipa-client oddjob-mkhomedir

### --- 2. Configure Time Synchronization (Chrony) --- ###
echo "[INFO] Configuring Chrony for time synchronization with xcatmn..."
cat << 'EOF' > /etc/chrony.conf
server 10.10.10.1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF

systemctl enable --now chronyd
chronyc reselect || true
chronyc makestep || true

### --- 3. Hostname Verification --- ###
NODE_FQDN=$(hostname -f)
echo "[INFO] Node FQDN resolved to: ${NODE_FQDN}"

### --- 4. FreeIPA Client Installation --- ###
if [ -f /etc/ipa/default.conf ]; then
    echo "[OK] FreeIPA client is already configured. Skipping join."
else
    echo "[INFO] Preparing Kerberos directory structure..."
    # Ensure /etc/krb5.conf.d exists with 755 permissions to prevent kinit initialization failures
    mkdir -p /etc/krb5.conf.d
    chmod 755 /etc/krb5.conf.d

    echo "[INFO] Joining FreeIPA domain CLUSTER.COM..."
    ipa-client-install \
        --unattended \
        --domain=cluster.com \
        --realm=CLUSTER.COM \
        --server=xcatmn.cluster.com \
        --hostname="${NODE_FQDN}" \
        --principal=admin \
        --password='rootroot' \
        --mkhomedir \
        --no-ntp \
        --force-join
fi

### --- 5. Configure FreeIPA Automount & PAM --- ###
echo "[INFO] Configuring FreeIPA Automount maps..."
ipa-client-automount --unattended --location=default || true

# Reduce autofs negative lookup caching timeout to 5 seconds
echo "[INFO] Configuring autofs negative_timeout..."
if grep -q "^negative_timeout" /etc/autofs.conf; then
    sed -i 's/^negative_timeout.*/negative_timeout = 5/' /etc/autofs.conf
else
    sed -i '/^\[autofs\]/a negative_timeout = 5' /etc/autofs.conf
fi

# Reduce autofs umount timeout
if grep -q "^timeout" /etc/autofs.conf; then
    sed -i -E 's/^#?timeout.*/timeout = 60/' /etc/autofs.conf
else
    sed -i '/^\[autofs\]/a timeout = 60' /etc/autofs.conf
fi

### --- 6. Configure SSSD Fast Cache Invalidation --- ###
echo "[INFO] Tuning SSSD cache timeouts..."
if [ -f /etc/sssd/sssd.conf ]; then
    if ! grep -q "entry_cache_timeout" /etc/sssd/sssd.conf; then
        sed -i '/\[domain\/cluster.com\]/a entry_cache_timeout = 10\nentry_cache_nowait_percentage = 0' /etc/sssd/sssd.conf || true
    fi
    if ! grep -q "negative_timeout" /etc/sssd/sssd.conf; then
        sed -i '/\[sssd\]/a negative_timeout = 5' /etc/sssd/sssd.conf || true
    fi
fi

echo "[INFO] Enabling home directory creation and activating services..."
systemctl enable --now oddjobd

# Enable PAM mkhomedir feature
authselect enable-feature with-mkhomedir || true

### --- 7. Flush Cache & Restart Authentication Services --- ###
echo "[INFO] Flushing SSSD cache and restarting services..."
systemctl stop autofs sssd
rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
systemctl enable --now sssd autofs

echo "[SUCCESS] Compute node postscript completed successfully."
```

### Step 2: Set Permissions and Assign to OS Image

```bash
chmod +x /install/postscripts/freeipa.sh
chdef -t osimage rocky8.10-x86_64-install-compute -p postscripts=freeipa.sh
```

---

# Phase 4: FreeIPA Administration & Operations

### 1. User Management Operations

- Add a new user

```bash
ipa user-add jdoe --first="John" --last="Doe" --password
```

- Reset/Set a user password

```bash
ipa passwd jdoe
```

- Delete a user and clean up local data

```bash
ipa user-del jdoe
```

- Clean up sssd cache on compute nodes if directory information stalls

```bash
sudo systemctl stop sssd
sudo rm -rf /var/lib/sss/db/*
sudo systemctl start sssd
```

### 2. Role-Based Access Control (RBAC)

- List available system roles

```bash
ipa role-find
```

- Assign a user to a specific role (use quotes if the role name contains spaces)

```bash
ipa role-add-member "User Management" --users=jdoe
```

---

## Phase 5: Troubleshooting & Uninstallation Procedures

### FreeIPA Uninstallation / Clean Reset

If a FreeIPA installation fails or requires a complete teardown on the Management Node, execute these commands in order:

1. Run the official uninstaller FIRST (Cleans up LDAP instances, Kerberos keys, and PKI certificates)

```bash
ipa-server-install --uninstall -U
```

1. Remove software packages

```bash
dnf remove freeipa-server -y
```

1. Remove orphaned systemd unit files and instance logs

```bash
systemctl stop dirsrv.target
rm -f /etc/systemd/system/httpd.service.d/ipa.conf
rm -f /usr/lib/systemd/system/httpd.service.d/ipa.conf
rm -rf /etc/dirsrv/slapd-CLUSTER-COM /var/lib/dirsrv/slapd-CLUSTER-COM /var/log/dirsrv/slapd-CLUSTER-COM
```

1. Reload daemon configs and restore unmasked named service

```bash
systemctl daemon-reload
systemctl unmask named
systemctl restart httpd
```