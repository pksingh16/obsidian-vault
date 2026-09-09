#!/bin/bash

# Registry nodes deployment script

# Deploy registry01
vm_id=2505
echo "Deploying registry01.r160a.local with VMID $vm_id in az1"

qm clone 100 "$vm_id" --name registry01.r160a.local --full true
qm set "$vm_id" --cores 4 --sockets 2 --memory 32768 \
    --ipconfig0 ip=10.50.4.21/25,gw=10.50.4.126 \
    --nameserver "10.50.2.131 10.50.2.133 10.50.2.132 10.50.2.134" \
    --net0 model=virtio,bridge=vmbr0,tag=119 \
    --searchdomain r160a.local
qm resize "$vm_id" scsi0 +590G
ha-manager add vm:"$vm_id" --state started --group az1

# Deploy registry02
vm_id=2506
echo "Deploying registry02.r160a.local with VMID $vm_id in az2"

qm clone 100 "$vm_id" --name registry02.r160a.local --full true
qm set "$vm_id" --cores 4 --sockets 2 --memory 32768 \
    --ipconfig0 ip=10.50.4.24/25,gw=10.50.4.126 \
    --nameserver "10.50.2.131 10.50.2.133 10.50.2.132 10.50.2.134" \
    --net0 model=virtio,bridge=vmbr0,tag=119 \
    --searchdomain r160a.local
qm resize "$vm_id" scsi0 +590G
ha-manager add vm:"$vm_id" --state started --group az2
