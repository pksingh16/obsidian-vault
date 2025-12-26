#!/bin/bash

# Master APPS Worker nodes deployment script
for i in $(seq -w 14 17); do
    num=$((10#$i))
    ip_last_octet=$((129 + num))
    vm_id="23$i"
    memory=98304
    # Assign to AZ based on index: 1-6 -> az1, 7-12 -> az2, 13 -> az3
    if [ "$num" -le 15 ]; then
        group_index=1
    else
        group_index=2
    fi

    echo "Deploying worker$i.apps.r160a.local to az${group_index}"

    qm clone 100 "$vm_id" --name worker$i.apps.r160a.local --full true
    qm set "$vm_id" --cores 16 --sockets 2 --memory ${memory} \
        --ipconfig0 ip=10.50.4.${ip_last_octet}/25,gw=10.50.4.254 \
        --nameserver "10.50.2.131 10.50.2.133 10.50.2.132 10.50.2.134" \
        --net0 model=virtio,bridge=vmbr0,tag=120 \
        --searchdomain r160a.local
    qm resize "$vm_id" scsi0 +190G
    ha-manager add vm:"$vm_id" --state started --group az${group_index}
done
