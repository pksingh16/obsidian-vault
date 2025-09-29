---
tags:
  - proxmox
---
# Snapshot Creation (Initial VM Setup sample)

```bash
#!/bin/bash
for vmid in 400 $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506); do
    echo "Creating snapshot for VMID $vmid..."
    qm snapshot "$vmid" initial-vm-setup  \
        --description "Only VM preparation with all ssh-key added to VM's from jumpbox and nopassword and visudo configuration & user added to group"  \
        --vmstate 0
done
```
