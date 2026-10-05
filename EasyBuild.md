# EasyBuild

# Step 1: Install Prerequisites

### **1. Required shell tools**

```bash
sudo dnf install -y tar gzip bzip2 xz patch rpm mlocate procps-ng unzip
```

### 2. python

```bash
sudo dnf install -y python3 python3-pip python3-devel
```

### **3. Required modules tool**

Run these commands to install `EPEL` and `Lmod`:

```bash
sudo dnf install -y epel-release && sudo dnf install -y Lmod
```

#### Verification & Setup

After installing, you must load the shell profile hooks to make the `module` function and `lmod` binary available in your `$PATH`:

1. Source the `Lmod` profile script for your current shell session:Bash

    ```bash
    source /etc/profile.d/modules.sh
    ```

2. Verify that the `module` function and path are detected:Bash

    ```bash
    type module
    ```

### 4. C/C++ compiler

```bash
sudo dnf install -y gcc gcc-c++
```

---

# **Step 2:Using pip to Install EasyBuild**

```bash
pip3 install easybuild
```

**Updating an existing EasyBuild installation**

```bash
pip3 install --upgrade easybuild
```

[Installation - EasyBuild - building software with ease](https://docs.easybuild.io/installation/)

---

# Step 3: **Configuring EasyBuild**

**Generating a template configuration file**

```bash
mkdir -p $HOME/.config/easybuild
eb --confighelp > $HOME/.config/easybuild/config.cfg
```

[Configuration - EasyBuild - building software with ease](https://docs.easybuild.io/configuration/)

---

# Step 4: Using the EasyBuild command line

- Search

```bash
eb -S <package name>
```

- install package with system default dependencies

```bash
eb <Package_name> --toolchain=system,system --robot
```

- Install a package with their required dependenices

```bash
eb <Package_name>  --robot
```

- To check if the OS package dependency issue is resolved without starting a full build, run a dependency dry-run first:

```bash
eb OpenMPI-4.1.4-GCC-11.3.0.eb --robot --dry-run
```

- the missing modules check:

```bash
eb OpenMPI-4.1.4-GCC-11.3.0.eb -M
```

---

## Overview of basic module commands

`*module avail*` - list the modules that are currently available to load

`*module load foss/2022a*` - load the module `foss/2022a`

`*module list*` - list currently loaded modules

`*module show foss/2022a*` - see contents of the module `foss/2022a` (shows the module functions instead of executing them)

`*module unload foss/2022a*` - unload the module `foss/2022a`

`*module purge*` - unload all currently loaded modules

```bash
tail -f /tmp/eb-*/easybuild-*.log # easybuild logs

```
---

# Step 5: create the `NFS` for shared modules

### On Management node:

1. create shared folder

```bash
mkdir /apps
```

1. install `nfs` server on the MN:

```bash
dnf install nfs-utils -y
```

1. Export /apps to cluster network:

```bash
echo "/apps 10.10.10.0/24(rw,sync,no_root_squash)" >> /etc/exports
```

1. Enable and start `NFS`

```bash
systemctl enable --now nfs-server
exportfs -r
```

### On compute nodes:

1. install `nfs` client:

    ```bash
    dnf install nfs-utils -y
    ```

2. Add mount to `/etc/fstab`:

    ```bash
    echo "10.10.10.1:/apps   /apps   nfs   defaults   0 0" >> /etc/fstab
    ```

3. Mount it

    ```bash
    mount -a
    ```

    ---

    # Step 6: integrate with xCAT

    1. create new file

    ```bash
     nano /install/postscripts/lmod.sh
    ```

    1. add next script

    ```bash
    #!/bin/bash
    set -eux

    yum install -y nfs-utils epel-release

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

    3. make it executable

    ```bash
    chmod +x /install/postscripts/lmod.sh
    ```

4. add to node as postbootscript

```bash
chdef cn1 -m postbootscripts=lmod.sh
```

# 1. Create the configuration directory

```bash
mkdir -p /etc/xdg/easybuild.d
```

# 2. Create the system-wide config file pointing to your shared path

```bash
cat << 'EOF' > //etc/xdg/easybuild.d/config.cfg
[config]
prefix = /app
installpath-software = /apps/software
installpath-modules = /apps/modules
EOF

eb --show-config
```
