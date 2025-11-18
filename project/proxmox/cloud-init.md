# Update cloud-init commandline

```bash
#!/bin/bash

# -------------------------------
# CONFIGURE USERNAME & PASSWORD
# -------------------------------
CI_USER="root"
CI_PASSWORD="HitachiPa55w0rd!"      # keep in quotes

# Generate a hashed password (recommended)
# If you want plaintext, comment this line
# CI_PASSWORD_HASH=$(mkpasswd -m sha-512 "$CI_PASSWORD")

# Set this to "--cipassword" to use plain text instead of hash
USE_HASH=false

# -------------------------------
# VM LIST
# -------------------------------
VM_LIST="200 \
$(seq 2301 2313) \
$(seq 2401 2405) \
$(seq 2411 2415) \
$(seq 2501 2506)"

echo "Updating cloud-init for VMs: $VM_LIST"
echo "Cloud-init Username: $CI_USER"
echo "Using password hash: $USE_HASH"
echo "-----------------------------------"

for vmid in $VM_LIST; do
    echo ""
    echo "=== Processing VMID $vmid ==="

    # Check if VM exists
    if ! qm config $vmid >/dev/null 2>&1; then
        echo "VM $vmid does not exist. Skipping."
        continue
    fi

#    echo "Stopping VM $vmid..."
#    qm stop $vmid >/dev/null 2>&1

    # Update cloud-init user and password
    if [ "$USE_HASH" = true ]; then
        echo "Setting hashed password..."
        qm set $vmid --ciuser "$CI_USER" --cipassword "$CI_PASSWORD_HASH"
    else
        echo "Setting plain text password..."
        qm set $vmid --ciuser "$CI_USER" --cipassword "$CI_PASSWORD"
    fi

    # Regenerate cloud-init seed
    echo "Regenerating cloud-init seed..."
    qm cloudinit update $vmid

    echo "Starting VM $vmid..."
    qm start $vmid >/dev/null 2>&1

    echo "VM $vmid updated successfully."
done

echo ""
echo "All cloud-init updates completed."

```
