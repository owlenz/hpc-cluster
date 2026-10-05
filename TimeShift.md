# TimeShift

## Step 1. Install Timeshift

Run:

```bash
sudo dnf install timeshift -y
```

---

## Step 2. Launch Timeshift

You can run it in two ways:

- **CLI (terminal)**:

    ```bash
    sudo timeshift --help
    ```

    or

    ```bash
    sudo timeshift --create --comments "Before Slurm"
    ```

- **GUI (desktop)**:

    If you have a desktop environment installed, just run:

    ```bash
    sudo timeshift-gtk
    ```

---

## Step 3. Initial Setup (first run)

When you first run Timeshift, it will ask:

1. **Backup type** → choose **RSYNC** (since you’re on XFS, not Btrfs). It’s picked by default
2. **Destination drive** → select a partition with enough free space (not your root, ideally another disk or big `/home`).

    ```bash
    sudo timeshift --snapshot-device /dev/mapper/rl-home
    ```

3. **Schedule** → you can enable daily/weekly/monthly backups.
4. **Filters** → By default, Timeshift protects system files (not user files like documents). That’s good because you usually want system restore, not personal files.

---

## Step 4. Create a Restore Point (manual)

Run:

```bash
sudo timeshift --create --comments "Before updates"
```

This will make a snapshot of your current system state.

---

## 🔹 Step 5. Restore if Something Breaks

Run:

```bash
sudo timeshift --restore
```

- Pick the snapshot you want.
- It will restore your system files and reboot into the saved state.

---

## Step 6. (Optional) Enable Scheduled Snapshots

we will use cron jobs for this one

```bash
# crontab -e # then add the following
0 2 * * * /usr/bin/timeshift --create --comments "scheduled" --tags D
0 3 * * * /usr/bin/timeshift --delete-all --older-than 7
```

- first job creates a snapshot daily at 2 am
- second job deletes snapshots older than 7 days everyday at 3 am
