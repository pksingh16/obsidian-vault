---
tags:
  - proxmox
---
# VM Deletion (Purge VMs except Jumpbox)

```bash
#!/bin/bash
echo "==== Purge all proxmox VM's except Jumpbox. ===="
for vmid in $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506); do
    echo "Deleting VMID $vmid..."
    qm destroy $vmid --purge
done
```
