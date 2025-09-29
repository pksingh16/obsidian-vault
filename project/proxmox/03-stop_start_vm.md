---
tags:
  - proxmox
---
# Stop or Start VM

## Stop VM's

```bash
#!/bin/bash
for vmid in 200 $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506); do
    echo "Stopping VMID $vmid..."
    qm stop $vmid
done
```

## Start VM's

```bash
for vmid in 200 $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506); do
    echo "Starting VMID $vmid..."
    qm start $vmid
done
```
