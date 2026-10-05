# xCAT management node setup

# Step 1: **Configure the Base OS Repository**

## 1.  Copy OS image to `/tmp` on the management node:

<aside>
💡

use DVD ISO to prevent the confirmation at installation

</aside>

- Using secure copy

    ```bash
    scp Rocky-8.10-x86_64-dvd1.iso root@10.10.10.1:/tmp
    ```

- Using USB
    1. get the name of the USB partition

        ```jsx
        lsblk
        ```


    2. create munt point

    ```jsx
    	mkdir -p /mnt/usb
    ```

    1. mount the usb

        ```jsx
        sudo mount /dev/sdb1 /mnt/usb
        ```

    2. copy the iso

        ```jsx
        cp /mnt/usb/Rocky-8.10-x86_64-dvd1.iso  /tmp
        ```


## 2. Mount the ISO to `/mnt/iso/rocky8.10` on the Management Node:

```bash
mkdir -p /mnt/iso/rocky8.10
mount -o loop /tmp/Rocky-8.10-x86_64-dvd1.iso /mnt/iso/rocky8.10
```

<aside>
✅

This warning is normal:

> `mount: /mnt/iso/rocky8.10: WARNING: device write-protected, mounted read-only.`
>
</aside>

---

# Step 2: **Configure the Management Node**

## 1. Set the hostname of *xcatmn.cluster.com*:

```bash
hostname xcatmn.cluster.com
```

## 2. Add the hostname to the `/etc/sysconfig/network` in order to persist the hostname on reboot:

```bash
sudo nano /etc/sysconfig/network
```

**paste and save:**

```bash
HOSTNAME=xcatmn.cluster.com
```

**Also set it in `/etc/hostname` :**

```bash
echo "xcatmn.cluster.com" | sudo tee /etc/hostname
```

**And add the following line in `/etc/hosts`:**

```bash
10.10.10.1  xcatmn.cluster.com   xcatmn
```

---

<aside>
💡

If you installed xCAT before setting up the hostname, write

```bash
chtab key = domain.in site.value=cluster.com
```

</aside>

---

# Step 3: Install xCAT Automatic

### 1. Download the `go-xcat` tool using `wget`:

```bash
wget https://raw.githubusercontent.com/xcat2/xcat-core/master/xCAT-server/share/xcat/tools/go-xcat -O -> /tmp/go-xcat

```

### 2. Make it executable

```jsx
chmod +x /tmp/go-xcat
```

### 3. Run the `go-xcat` tool:

```bash

**/tmp/go-xcat -x 2.16 install
```

<aside>
📌

Note: change the version of 2.16 to the version you desire. You can find details about the versions here :

> [https://xcat-docs.readthedocs.io/en/2.16.5/overview/xcat2_release.html](https://xcat-docs.readthedocs.io/en/2.16.5/overview/xcat2_release.html)
and
[https://xcat.org/files/xcat/repos/yum/](https://xcat.org/files/xcat/repos/yum/)
>
</aside>

---

# Step 4: **Verify xCAT Installation**

## 1. Source the profile to add xCAT Commands to your path:

```bash
source /etc/profile.d/xcat.sh
```

## 2. Check the xCAT version:

```bash
lsxcatd -a
```

## 3. Check to verify that the xCAT database is initialized by dumping out the site table

```bash
tabdump site
```

---

# Step 5: **Starting and Stopping**

## - Start xCAT:

```bash
systemctl start xcatd.service
```

## -  Stop xCAT:

```bash
systemctl stop xcatd.service
```

## -  Restart xCAT:

```bash
systemctl restart xcatd.service
```

## -  Check xCAT status:

```bash
systemctl status xcatd.service
```

---

# Step 6: Run the `xcatprobe xcatmn` and solve the errors

## Run the Next Command

```bash
xcatprobe xcatmn
```

if you get the next fails you will need to fix them as follows:

![image.png](assets/xCAT%20management%20node%20setup/18509e3a-f33b-49b7-94ec-2664b5079ba7.png)

### Fixing `SELinux` [WARN]

```bash
setenforce 0
SELINUX=disabled
reboot
```

### Fixing `No interface provided by ‘-i’ option`

1. get your network interface name:

```bash
ip addr show
```

for example “enp0s31f6”, then run xcatprobe as follows:

```bash
xcatprobe xcatmn -i enp0s31f6
```

### Fixing `passwd` [FAIL]

```bash
chtab key=system passwd.username=root passwd.password=root
```

### Fixing `DHCP` [FAIL]

```jsx
chdef -t network -o 10_10_10_0-255_255_255_0 dynamicrange=10.10.10.20-10.10.10.30
makedhcp -n
```

### Fixing `DNS` [FAIL]

1. Check if the DNS service is running

```bash
sudo systemctl status named
```

If you see **inactive** or **failed**, start it:

```bash
sudo systemctl enable named --now
```

1. Go to the `nmtui` and add the IP address of your server in the DNS. Make sure to make it the **FIRST** IP Address

```bash
sudo nmtui
```

![Screenshot from 2025-08-11 11-58-02.png](xCAT%20management%20node%20setup/Screenshot_from_2025-08-11_11-58-02.png)

1. Go to the `/etc/resolv.conf` and add the `nameserver 10.10.10.1`

```bash
sudo nano /etc/resolv.conf
```

add to at the top of the file

```bash
nameserver 10.10.10.1
```

1. Test it.

```bash
dig $(hostname)@10.10.10.1
```

### If it failed do run these commands

This adds your management node to xCAT’s database so other xCAT commands (like `makedns`) know it exists and what its DNS entry should be.

```bash
xcatconfig -m
chdef -t node -o xcatmn ip=10.10.10.1 hostnames=xcatmn.cluster.com
```

This takes your node definitions and turns them into actual DNS records so they can be resolved.

```bash
makedns -n
systemctl restart named
```

verify

```bash
dig xcatmn.cluster.com@10.10.10.1
dig -x 10.10.10.1@10.10.10.1
```

### Fixing `NTP` [FAIL]

1. Make sure chrony is installed:

```bash
dnf install chrony
```

1. Add these lines to /etc/chrony.conf :

```bash
local stratum 10

allow 10.53.90.0/24
allow 127.0.0.1
```

1. Make sure `chronyd` is running:

```bash
systemctl enable chronyd
systemctl start chronyd
```

### Fixing `rsyslog` [FAIL]:

```bash
dnf install rsyslog
systemctl enable --now rsyslog
systemctl status rsyslog
```

---

# Step 7: **Provision a node and manage it**

## 1. Add a node

```bash
mkdef -t node cn1 \
  ip=10.10.10.2 \
  mac=e0:db:55:12:a3:6c \
  groups=all \
  netboot=pxe \
  mgt=ipmi \
  bmc=10.10.10.120 \
  bmcusername=root \
  bmcpassword=root \
  hostnames=cn1.cluster.com
```

## 2. Configure DNS & DHCP with cn1:

```bash
makehosts cn1
makedns -n
makedhcp -n
```

## 3. Prepare the OS image:

```bash
copycds /tmp/Rocky-8.10-x86_64-dvd1.iso
```

## 4. Check available osimages:

```bash
lsdef -t osimage
```

## 5. Use `nodeset` to start provisioning:

```bash
nodeset cn1 osimage=rocky8.10-x86_64-install-compute
```

## 6. Copy `bootloader` modules to /tftpboot:

```bash
sudo cp /usr/share/syslinux/ldlinux.c32 /tftpboot/
sudo cp /usr/share/syslinux/menu.c32 /tftpboot/
sudo cp /usr/share/syslinux/libutil.c32 /tftpboot/
```

To monitor the progress of the provisioning :

```jsx
xcatprobe osdeploy -n <compute node name>
```

<aside>
💡

Then restart the Compute Node manually and make sure it is set to network boot

</aside>

---

<aside>
💡

In case of connecting nodes back to back and having 2 network cards remove the default route of the nic connected back to back:

```bash
sudo nmcli connection modify enp0s31f6 ipv4.never-default yes
sudo nmcli connection up enp0s31f6
```

</aside>

---

# Create Custom Repo

1. install needed packkages on the MN:

    ```bash
    # Tools you’ll need
    sudo dnf install -y dnf-plugins-core createrepo_c epel-release
    ```

2. Create your repo to be used by the CNs:

    ```bash
    mkdir -p /install/repo/custom_repo
    ```

3. Go to your created repo and populate it with all your needed packages:

    ```bash
    cd /install/repo/custom_repo
    dnf download --resolve free-ipa-client
    dnf download --resolve epel-release
    dnf download --resolve lua-filesystem lua-term lua-posix
    ```

4. Create the repo after filling in all the packages:

    ```bash
    createrepo /install/repo/custom_repo
    ```


1. Create your repo file on the MN pointing to the repo we just created on the MN:

    ```bash
    cat >/install/repo/custom_repo.repo <<'EOF'
    [custom_repo]
    name=My Local Repo
    baseurl=http://10.10.10.1/install/repo/custom_repo
    enabled=1
    gpgcheck=0
    EOF
    ```


6. make sure `httpd` is running on the MN and can serve your repo file:

```bash
systemctl status httpd
curl http://10.10.10.1/install/repo/custom_repo/
curl http://10.10.10.1/install/repo/custom_repo/repodata/repomd.xml
```

7. Create a **`synclist`** to copy repo config into nodes:

```bash
cat >/install/custom.synclist <<'EOF'
/install/repo/custom_repo.repo -> /etc/yum.repos.d/custom_repo.repo
EOF
```

8. Attach the synclist to your OS image:

```bash
chdef -t osimage rocky8.9-x86_64-install-compute synclists=/install/custom.synclist
```

<aside>
✅

Now this repo will be visible to any newly provisioned CNs

</aside>

<aside>
💡

In case of creating new repos on the MN, we will need to run

```bash
updatenode cn1 -F
```

to let the CN know that new repos were created and have the repo config file with the new repo link on the MN.

</aside>

## 7. Create a yum repository file `/etc/yum.repos.d/Rocky-8.9-local.repo` that points to the locally mounted iso image from the above step:

```bash
[Rocky-8.9-BaseOS]
name=Rocky Linux 8.9 BaseOS
baseurl=file:///mnt/iso/rocky8.9/BaseOS
enabled=1
gpgcheck=0

[Rocky-8.9-AppStream]
name=Rocky Linux 8.9 AppStream
baseurl=file:///mnt/iso/rocky8.9/AppStream
enabled=1
gpgcheck=0
```

# Step 10: Add packages to provisioned nodes:

## 1. If package already exists in Rocky 8 local repos: ****

1. **Use  `xdsh`**

    ```bash
    xdsh <noderange> "dnf install -y git"
    ```

    **When to use:**

    - You want to quickly run **one or two commands** across nodes.
    - You don’t care about saving/reusing the logic later.
    - It’s a **one-off operation** (e.g., “just install `git` on all nodes now”)

2. **Use `updatenode` with a postscript**
    - Create a custom script in `/install/postscripts/`, e.g. `mypkgs.sh`:

    ```bash
    nano /install/postscripts/mypkgs.sh
    ```

    Inside [`mypkgs.sh`](http://mypkgs.sh) we can add:

    ```bash
    #!/bin/bash
    #!/bin/bash

    sudo yum install -y vim wget htop
    sudo dnf install -y nfs-utils
    sudo dnf install -y epel-release
    sed -i 's/\#baseurl=https:\/\/download.example\/pub\/epel\/8\/Everything\/\$basearch/baseurl=http:\/\/10.10.10.1\/install\/repo\/custom_repo/g' /etc/yum.repos.d/epel.repo
    sudo dnf install -y Lmod

    sudo echo "10.10.10.1:/apps     /apps   nfs     defaults        0 0" >> /etc/fstab
    mount -a
    [[ $? -eq 0 ]] && echo "Mounted NFS export /apps"

    source /etc/profile.d/modules.sh
    [[ $? -ne 0 ]] && echo "couldnt source modules.sh error code: $?"
    module use /apps/modules/all/

    ```

    Then push it to the node(s):

    ```bash
    updatenode <noderange> -P mypkgs.sh
    ```

    **When to use:**

    - You want a **scripted, reusable setup** (a postscript in `/install/postscripts/`).
    - You expect to run it multiple times (e.g., after reprovisioning nodes).
    - You need **multi-step installs** or environment setup (not just one command).

## 2. If package isn’t included and need internet access:

1. Using xdcp/xdsh from xcatmn:

    ```bash
    # Install repo with this package of the management node:
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -O ~/epel-release-latest-8.noarch.rpm

    # copy the repo to compute nodes:
    xdcp cn1 ~/epel-release-latest-8.noarch.rpm /tmp/

    # Then remotely install the previously unavailable package:
    xdsh cn1 "dnf install -y /tmp/epel-release-latest-8.noarch.rpm"
    ```

2. Add packages to install to pkglist and otherpkglist on the osimage to install them during provisioning the node.

## Use environment modules (Lmod) .2

- Instead of installing packages system-wide, you can deliver tools via modulefiles.
- Common in HPC environments where users want multiple versions of tools.
- this requires changing the postscript to the following

```bash
#!/bin/bash
set -eux

yum install -y vim wget nfs-utils epel-release

sed -i 's/\#baseurl=https:\/\/download.example\/pub\/epel\/8\/Everything\/\$basearch/baseurl=http:\/\/10.10.10.1\/install\/repo\/custom_repo/g' /etc/yum.repos.d/epel.repo

dnf clean all
dnf makecache

dnf install -y Lmod

mkdir /apps
echo "10.10.10.1:/apps  /apps   nfs     defaults        0 0" >> /etc/fstab
mount -a && echo "Mounted NFS export /apps"

source /etc/profile.d/modules.sh || echo "couldn't source modules.sh"
module use /apps/modules/all/
```

now we can use easybuild on the MN to add any package the CN would need and pull it from there using Lmod’s module command

## 3. Create repos on MN and use synclist to push the repo to cn to be installed on demand or auto via postscripts:

1. install needed packages on the MN:

    ```bash
    # Tools you’ll need
    dnf install -y dnf-plugins-core createrepo_c
    sudo dnf install epel-release
    ```


1. Create your repo to be used by the CNs:

    ```bash
    mkdir -p /install/repo/custom_repo
    ```


1. Go to your created repo and populate it with all your needed packages:

    ```bash
    dnf download --resolve free-ipa-client
    ```

2. Create the repo after filling in all the packages:

    ```bash
    createrepo /install/repo/custom_repo
    ```


1. Create your repo file on the MN pointing to the repo we just created on the MN:

    ```bash
    cat >/install/repo/custom_repo.repo <<'EOF'
    [custom_repo]
    name=My Local Repo
    baseurl=http://20.20.20.1/install/repo/custom_repo
    enabled=1
    gpgcheck=0
    EOF
    ```


6. make sure httpd is running on the MN and can serve your repo file:

```bash
systemctl status httpd
curl http://20.20.20.1/install/repo/custom_repo/
curl http://20.20.20.1/install/repo/custom_repo/repodata/repomd.xml
```

7. Create a **synclist** to copy repo config into nodes:

```bash
cat >/install/custom.synclist <<'EOF'
/install/repo/custom_repo.repo -> /etc/yum.repos.d/custom_repo.repo
EOF
```

8. Attach the synclist to your OS image:

```bash
chdef -t osimage rocky8.9-x86_64-install-compute synclists=/install/custom.synclist
```

<aside>
✅

Now this repo will be visible to any newly provisioned CNs

</aside>

<aside>
💡

In case of creating new repos on the MN, we will need to run

```bash
updatenode cn1 -F
```

to let the CN know that new repos were created and have the repo config file with the new repo link on the MN.

</aside>

## 4. Updating already created repos and syncing that with already provisioned CNs:

1. Download the new packages you want to add:

    ```bash
    yumdownloader --destdir=/install/repo/custom_repo sl
    ```

2. After adding new RPMs into that repo, run:

    ```bash
    createrepo --update /install/repo/custom_repo
    ```

    to update the already created repo

3.  On the CN run:

    ```bash
    dnf clean all
    dnf makecache
    dnf install sl
    ```


# OS Image backup

### Metadata backup

```bash
# Export single osimage definition
lsdef -t osimage <osimage_name> -z > /root/osimage_<osimage_name>.def
```

**Step 2**: Identify file locations

```bash
lsdef -t osimage rocky8.9-x86_64-install-compute -i rootimgdir,osdistroname,pkgdir,otherpkgdir
```

**step 3**

create backup dir

```bash
mkdir -p rocky8.9-x86_64-install-compute
```

copy files into the backup dir

```bash
cp -a /install/rocky8.9/x86_64 /backup/osimages/rocky8.9-x86_64-install-compute/
cp -a /install/repo/custom_repo /backup/osimages/rocky8.9-x86_64-install-compute/
cp -a /install/post/otherpkgs/rocky8.9/x86_64 /backup/osimages/rocky8.9-x86_64-install-compute/
```

copy iso

```bash
cp /tmp/Rocky-8.9-x86_64-dvd1.iso /backup/osimages/
```

**step 4**

compress

```bash
tar -czf /backup/osimages/rocky8.9-x86_64-install-compute.tar.gz -C /backup/osimages rocky8.9-x86_64-install-compute
```

### Restore later

1. Extract repos back:

    ```
    tar -xzf /backup/osimages/rocky8.9-x86_64-install-compute.tar.gz -C /install/
    ```

2. re-import definition

    ```bash
    mkdef -z < /root/rocky8.9-x86_64-install-compute.def
    ```

3. rebuild repo metadata (if needed)

    ```bash
    createrepo /install/rocky8.9/x86_64
    createrepo /install/repo/custom_repo
    createrepo /install/post/otherpkgs/rocky8.9/x86_64
    ```


1. **Copy the ISO manually** somewhere else, e.g.:

    ```bash
    mount -o loop /path/to/new.iso /mnt
    rsync -a /mnt/ /install/rocky9.3-x86_64-custom/
    umount /mnt

    ```

2. **Define a new osimage** pointing to this custom path:

    ```bash
    mkdef -t osimage rocky9.3-custom-x86_64 \
        osvers=rocky9.3 \
        osarch=x86_64 \
        provmethod=install \
        profile=compute \
        osdistroname=rocky9.3-x86_64-custom

    ```


That way, you’ll have **two separate install trees** and xCAT won’t overwrite the first one.

# if the root space is Full

### Step 1: Create a directory under `/home`

```bash
mkdir /home/xcat-install

```

---

### Step 2: Mount ISO into `/mnt` (already done, but let’s be sure)

```bash
umount /mnt   # if still mounted
mount -o loop /tmp/Rocky-8.9-x86_64-dvd1.iso /mnt

```

---

### Step 3: Copy ISO contents into `/home/xcat-install`

```bash
rsync -a /mnt/ /home/xcat-install/rocky8.9-x86_64-slurm/

```

---

### Step 4: Tell xCAT about this path

When you define the osimage, set its `osdistroname` to match the new directory name:

```bash
mkdef -t osimage rocky8.9-slurm-x86_64 \
    osvers=rocky8.9 \
    osarch=x86_64 \
    provmethod=install \
    profile=compute \
    osdistroname=rocky8.9-x86_64-slurm
```

Then in `linuxdistro` table, point it to the `/home/xcat-install/...` path:

```bash
chdef -t osdistro rocky8.9-x86_64-slurm dir=/home/install/rocky8.9-x86_64-slurm
```

#

# (Under Testing) Enable the compute node to access the internet:

## Enable IP Forwarding on PC1

Edit sysctl:

```jsx
sudo nano /etc/sysctl.conf
```

Uncomment or add:

```jsx
net.ipv4.ip_forward = 1
```

Apply immediately:

```jsx
sudo sysctl -p
```

nodeset cn1 osimage=rocky8.9-x86_64-install-compute

## Assign IP Addresses

### On PC1 (internal NIC → PC2) :

```jsx
sudo nmcli con mod ens37 ipv4.addresses 192.168.10.1/24
sudo nmcli con mod ens37 ipv4.method manual
sudo nmcli con up ens37
```

### On PC2 :

```jsx
sudo nmcli con mod ens33 ipv4.addresses 192.168.10.2/24
sudo nmcli con mod ens33 ipv4.gateway 192.168.10.1
sudo nmcli con mod ens33 ipv4.dns 8.8.8.8
sudo nmcli con mod ens33 ipv4.method manual
sudo nmcli con up ens33

```

## Adding NAT rule with iptables:

### On PC1 , run :

```jsx
# Replace enp0s31f6 with the NIC connected to Internet
sudo iptables -t nat -A POSTROUTING -o enp0s31f6 -j MASQUERADE

# Allow forwarding
sudo iptables -A FORWARD -i enp0s31f6 -o enp5s0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i enp5s0 -o enp0s31f6 -j ACCEPT
```

<aside>
💡

enp0s31f6 → your Internet NIC

enp5s0 (example) → your internal NIC to PC2 (replace with actual name)

</aside>

sudo systemctl edit --full httpd

rm /etc/systemd/system/httpd.service.d/ipa.conf
rm /usr/lib/systemd/system/httpd.service.d/ipa.conf

sudo systemctl daemon-reload
sudo systemctl restart httpd

sudo systemctl unmask named

xcatconfig -m

mkdef -t node -o cn1 ip=10.53.90.91 mac=c8:d9:d2:2b:ca:71 netboot=xnba groups=all

chdef -t site extntpservers=10.53.135.135

nslookup [xcatmn.cluster.com](http://xcatmn.cluster.com/)
218  nslookup 20.20.20.1

watch -n 1 "systemctl status dhcpd”
chtab key=system passwd.username=root passwd.password=admin

xcatprobe osdeploy -n cn1

postscripts=syslog,remoteshell,syncfiles

/opt/xcat/share/xcat/install/rocky/compute.rocky8.pkglist

chdef -t osimage rocky8.9-x86_64-install-compute otherpkgdir="/install/repo/custom_repo , /install/post/otherpkgs/rocky8.9/x86_64”

chdef -t osimage rocky8.9-x86_64-install-compute otherpkglist=/install/custom.pkglist

/install/postscripts/mypkgs.sh
