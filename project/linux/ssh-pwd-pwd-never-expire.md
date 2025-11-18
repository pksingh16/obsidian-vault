# SSH Reset Password to Never Expire

Reset password expiry → NEVER EXPIRE

ansible user for all VMs

thales user only for VMID 200

All done automatically.

```bash
#!/bin/bash

# ====== CONFIGURATION ======
# SSH user who has permissions to delete /var/lib/rook
SSH_USER="ansible"

# List of hosts
HOSTS=(
  master01.apps.r160a.local
  master02.apps.r160a.local
  master03.apps.r160a.local
  master04.apps.r160a.local
  master05.apps.r160a.local
  master01.ops.r160a.local
  master02.ops.r160a.local
  master03.ops.r160a.local
  master04.ops.r160a.local
  master05.ops.r160a.local
  worker01.apps.r160a.local
  worker02.apps.r160a.local
  worker03.apps.r160a.local
  worker04.apps.r160a.local
  worker05.apps.r160a.local
  worker06.apps.r160a.local
  worker07.apps.r160a.local
  worker08.apps.r160a.local
  worker09.apps.r160a.local
  worker10.apps.r160a.local
  worker11.apps.r160a.local
  worker12.apps.r160a.local
  worker13.apps.r160a.local
  registry01.r160a.local
  registry02.r160a.local
  loadbalancer01.apps.r160a.local
  loadbalancer02.apps.r160a.local
  loadbalancer03.apps.r160a.local
  loadbalancer04.apps.r160a.local
)

# ====== RESET PWD EXPIRY ======
for HOST in "${HOSTS[@]}"; do
    echo "🔧 Resetting pwd expiry on $HOST ..."

    ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" bash <<'EOF'
sudo sudo chage -M 99999 ansible
EOF

done

echo "✅ Completed Resetting pwd expiry on all hosts."

```
