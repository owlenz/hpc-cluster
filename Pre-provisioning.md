# Pre-provisioning

# Step 1:  Install OS on Management Node

we will Install Rocky Linux

Make sure to update the package manager first thing:

```bash
sudo dnf update
sudo dnf upgrade
```

---

# Step 2: Edit the Network Configuration

## 1. Open Network configuration

```bash
sudo nmtui
```

## 2. Open the Settings of Ethernet

> Edit a connection —> enp0s31f6

## 3. Edit the Connection like the following

![image.png](assets/Pre-provisioning/image.png)

## 4. Back to Network Manger TUI page

> OK —> Back

## 5. Activate a connection

> Activate a connection —> Deactivate —> Activate

---
