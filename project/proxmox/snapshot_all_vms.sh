#!/bin/bash

# Snapshot prefix to search for
SNAP_PREFIX="pre-tvp-install-"

# Array of VM IDs
VMIDS=(6101 6102 6103 62001 62002 62003 62004 62005 62006 62007 62008 62009 62010 62011 62012 62013 62014 62015 6301 6302 6303)

echo "Starting snapshot restoration with prefix: $SNAP_PREFIX"
echo "=========================================="

for vmid in "${VMIDS[@]}"
do
    echo "Processing VMID $vmid"
    
    # Get snapshot name with the prefix
    SNAPNAME=$(qm listsnapshot $vmid | grep "$SNAP_PREFIX" | awk '{print $2}' | head -n 1)
    
    if [ -z "$SNAPNAME" ]; then
        echo "  WARNING: No snapshot found with prefix '$SNAP_PREFIX' for VM $vmid"
        echo "----------------------------------"
        continue
    fi
    
    echo "  Found snapshot: $SNAPNAME"
    
    # Check if VM is running and stop it
    if qm status $vmid | grep -q "running"; then
        echo "  Stopping VM $vmid..."
        qm stop $vmid
        sleep 2
    fi
    
    echo "  Restoring snapshot '$SNAPNAME' for VM $vmid..."
    qm rollback $vmid $SNAPNAME
    
    echo "  Snapshot restored for $vmid"
    echo "----------------------------------"
done

echo "All snapshot restorations completed."
echo "VMs are stopped. Start them manually with: qm start <vmid>"
