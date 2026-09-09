#!/bin/bash

# Master OPS Master nodes deployment script
for i in $(seq -w 1 5)
do
   num=$((10#$i))
   vm_id=$((2400 + num))
   ip_last_octet=$((10 + num))  # IPs 11-15

   # Assign AZs: 2 in az1, 2 in az2, 1 in az3
   if [ "$num" -le 2 ]; then
       az="az1"
   elif [ "$num" -le 4 ]; then
       az="az2"
   else
       az="az3"
   fi

   echo "Creating master0${i}.ops.r160a.local (VMID ${vm_id}) in ${az}"
   qm clone 100 ${vm_id} --name master0${i}.ops.r160a.local --full true

   qm set ${vm_id} \
     --cores 2 \
     --sockets 2 \
     --memory 16384 \
     --ipconfig0 ip=10.50.4.${ip_last_octet}/25,gw=10.50.4.126 \
     --nameserver "10.50.2.131 10.50.2.133 10.50.2.132 10.50.2.134" \
     --net0 model=virtio,bridge=vmbr0,tag=119 \
     --searchdomain r160a.local

   qm resize ${vm_id} scsi0 +190G
   ha-manager add vm:${vm_id} --state started --group ${az}

   echo "master0${i}.ops.r160a.local created successfully in ${az}"
done

echo "All Master OPS nodes deployment completed!"
