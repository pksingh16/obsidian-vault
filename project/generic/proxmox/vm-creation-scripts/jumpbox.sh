#!/bin/bash

# Jumpbox node deployment script
vm_id=400

echo "Deploying jumpbox.r160a.local with VMID $vm_id in az1"

# Clone the base template
qm clone 100 "$vm_id" --name jumpbox.r160a.local --full true

# Set Cloud-Init user and password
qm set "$vm_id" \
    --ciuser thales \
    --cipassword 'HitachiPa55!'

# Set CPU, memory, network, and domain
qm set "$vm_id" \
    --cores 4 \
    --sockets 2 \
    --memory 65536 \
    --ipconfig0 ip=10.50.4.10/25,gw=10.50.4.126 \
    --net0 model=virtio,bridge=vmbr0,tag=119 \
    --searchdomain r160a.local

# Resize the disk
qm resize "$vm_id" scsi0 +390G

# Add VM to HA group
ha-manager add vm:"$vm_id" --state started --group az1
