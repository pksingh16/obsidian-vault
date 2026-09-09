#!/bin/bash

# HAProxy VMs configuration
for i in $(seq -w 1 4)  # i = 01, 02, 03, 04
do
    num=$((10#$i))  # num = 1, 2, 3, 4
    vm_id=$((2500 + num))
    ip_last_octet=$((129 + num))

    # Assign first 2 VMs to az1, next 2 to az2
    if [ "$num" -le 2 ]; then
        az="az1"
    else
        az="az2"
    fi

    formatted_i=$(printf "%02d" $num)  # Ensure the format is always two digits

    echo "Creating VM $vm_id with name loadbalancer$formatted_i.apps.r160a.local in $az"

    qm clone 100 $vm_id --name "loadbalancer${formatted_i}.apps.r160a.local" --full true
    qm set $vm_id --cores 1 --sockets 1 --memory 1024 \
        --ipconfig0 ip=10.50.1.${ip_last_octet}/26,gw=10.50.1.190 \
        --nameserver "10.50.2.131 10.50.2.133 10.50.2.132 10.50.2.134" \
        --net0 model=virtio,bridge=vmbr0,tag=113 \
        --searchdomain r160a.local
    qm resize $vm_id scsi0 +190G
    ha-manager add vm:$vm_id --state started --group $az
done
