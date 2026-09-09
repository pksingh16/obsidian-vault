---
tags:
  - proxmox
---
# Update VM Cloud-Init Configuration

## For Jumpbox VM

```bash
#!/bin/bash
vmid=200
echo "Updating VMID $vmid..."
qm set $vmid  \
    --ciuser ansible  \
    --cipassword 'HitachiPa55!'  \
    --nameserver "10.50.2.131 10.50.2.133 10.50.2.134"  \
    --searchdomain r160a.local
qm cloudinit update $vmid
```

## For all VM's

```bash
#!/bin/bash
for vmid in $(seq 2301 2313) $(seq 2401 2405) $(seq 2411 2415) $(seq 2501 2506); do
    echo "Updating VMID $vmid..."
    qm set $vmid  \
        --ciuser ansible  \
        --cipassword 'HitachiPa55!'  \
        --nameserver "10.50.2.131 10.50.2.133 10.50.2.134"  \
        --searchdomain r160a.local
    qm cloudinit update $vmid
done
```
