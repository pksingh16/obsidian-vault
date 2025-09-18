---
tags:
  - proxmox
---
# Snapshot Deletion (Specific Snapshots)

```bash
# VM list
VM_LIST="200 $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506)"

# Snapshot names to delete
SNAPSHOTS=("working-cctv-configuration-20250728-1132" "TVP-15_6")

for vmid in $VM_LIST; do
    echo "Processing VMID $vmid..."
    for snap in "${SNAPSHOTS[@]}"; do
        if qm listsnapshot $vmid | awk '{print $2}' | grep "$snap"; then
            echo "Deleting snapshot '$snap' for VMID $vmid..."
            qm delsnapshot $vmid "$snap"
        else
            echo "Snapshot '$snap' not found on VMID $vmid, skipping..."
        fi
    done
done
echo "Snapshot deletion process completed."
```
