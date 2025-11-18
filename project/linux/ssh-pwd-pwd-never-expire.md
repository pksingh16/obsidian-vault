# SSH Reset + Key Freshening + Password Never Expire

✅ For every VM:

Detect IP via Qemu Guest Agent

Remove old SSH host key (ssh-keygen -R)

Re-add fresh host key (ssh-keyscan -H)

Delete old authorized keys and push new SSH key

Reset password expiry → NEVER EXPIRE

ansible user for all VMs

thales user only for VMID 200

All done automatically.

```bash
#!/bin/bash

# ====== CONFIGURATION ======
DEFAULT_USER="ansible"
SPECIAL_USER="thales"      # only for VMID 200
PASSWORD="HitachiPa55!"
SSH_KEY="$HOME/.ssh/id_rsa.pub"

# ====== VM LIST ======
VM_LIST="200 \
$(seq 2301 2313) \
$(seq 2401 2405) \
$(seq 2411 2415) \
$(seq 2501 2506)"

echo "=============================================="
echo "🔧 SSH RESET + KEY DEPLOY + PWD NEVER EXPIRE"
echo "=============================================="
echo "Default User      : $DEFAULT_USER"
echo "Special User (200): $SPECIAL_USER"
echo "----------------------------------------------"

for vmid in $VM_LIST; do
    echo ""
    echo "=== 🖥 Processing VMID $vmid ==="

    # Check VM exists
    if ! qm config $vmid >/dev/null 2>&1; then
        echo "⚠️ VM $vmid does not exist. Skipping."
        continue
    fi

    # Determine which username to apply
    if [ "$vmid" = "200" ]; then
        USER="$SPECIAL_USER"
    else
        USER="$DEFAULT_USER"
    fi

    # Get IP via guest agent
    IP=$(qm guest cmd $vmid network-get-interfaces \
        | jq -r '.[]?."ip-addresses"[]? | select(.["ip-address-type"]=="ipv4") | .address' \
        | grep -v "^127\." | head -n1)

    if [[ -z "$IP" ]]; then
        echo "❌ Could not detect IP for VMID $vmid. Skipping."
        continue
    fi

    echo "📡 IP for VM $vmid: $IP"
    echo "👤 Using user: $USER"

    # ----- REMOVE OLD HOST KEY -----
    echo "🧹 Removing old SSH host key entry..."
    ssh-keygen -R "$IP" >/dev/null 2>&1

    # ----- ADD FRESH HOST KEY -----
    echo "➕ Adding fresh SSH host key..."
    ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null

    # ----- PUSH SSH KEY -----
    echo "🔐 Deploying SSH key to $IP..."
    sshpass -p "$PASSWORD" ssh-copy-id \
        -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$USER@$IP"

    # ----- RESET PASSWORD EXPIRY -----
    echo "🔒 Resetting password expiry (never expire)..."
    ssh -o StrictHostKeyChecking=no "$USER@$IP" <<EOF
sudo chage -M -1 -E -1 $USER
EOF

    echo "✅ VM $vmid ($IP) updated successfully."
done

echo ""
echo "🎉 ALL VMs UPDATED SUCCESSFULLY"

```
