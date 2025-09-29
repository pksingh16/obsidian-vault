---
tags:
  - proxmox
---
# Snapshot Creation – Complete VM Setup

```bash
# VM list
VM_LIST="200 $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506)"

# Snapshot details
SNAP_NAME="complete-vm-setup"
SNAP_DESC="Complete VM preparation and configuration for TVP 15.6 with root password and user password set."

for vmid in $VM_LIST; do
    echo "Creating snapshot '$SNAP_NAME' (without RAM state) for VMID $vmid..."
    qm snapshot $vmid "$SNAP_NAME" --description "$SNAP_DESC" --vmstate 0
    if [ $? -eq 0 ]; then
        echo "✅ Snapshot created successfully for VMID $vmid"
    else
        echo "❌ Failed to create snapshot for VMID $vmid"
    fi
done

echo "All snapshot operations completed."
```
