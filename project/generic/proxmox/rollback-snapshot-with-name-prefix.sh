#!/bin/bash

# Proxmox VM Snapshot Rollback Script
# Rollback snapshots with prefix 'tvp_preparation_*' for specified VM ID ranges

# Note: set -e is NOT used so script continues even if individual VMs fail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SNAPSHOT_PREFIX="tvp_preparation_"

# VM ID ranges to process
VM_RANGES=(
    "201:203"
    "211:230"
    "301:303"
    "311:330"
)

# Function to find the latest snapshot with the specified prefix
find_latest_snapshot() {
    local vmid=$1
    local snapshots
    
    # Get list of snapshots for the VM
    # Proxmox output format: `-> snapshot_name timestamp description
    # We need to extract just the snapshot name after the `-> prefix
    snapshots=$(qm listsnapshot "$vmid" 2>/dev/null | \
                grep "${SNAPSHOT_PREFIX}" | \
                sed 's/^`-> //' | \
                awk '{print $1}' | \
                grep "^${SNAPSHOT_PREFIX}" | \
                sort -r)
    
    if [ -z "$snapshots" ]; then
        return 1
    fi
    
    # Return the first (latest) snapshot
    echo "$snapshots" | head -n 1
}

# Function to rollback a VM to a snapshot
rollback_vm() {
    local vmid=$1
    local snapshot=$2
    
    echo -e "${YELLOW}Rolling back VM ${vmid} to snapshot '${snapshot}'...${NC}"
    
    if qm rollback "$vmid" "$snapshot" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully rolled back VM ${vmid} to snapshot '${snapshot}'${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to rollback VM ${vmid}, continuing...${NC}"
        return 1
    fi
}

# Function to check if VM exists
vm_exists() {
    local vmid=$1
    qm status "$vmid" &>/dev/null
    return $?
}

# Main execution
echo "================================================"
echo "Proxmox VM Snapshot Rollback"
echo "Snapshot Prefix: ${SNAPSHOT_PREFIX}*"
echo "================================================"
echo ""

success_count=0
failed_count=0
skipped_count=0

# Process each VM range
for range in "${VM_RANGES[@]}"; do
    IFS=':' read -r start end <<< "$range"
    
    echo -e "${YELLOW}Processing VM range: ${start} to ${end}${NC}"
    echo "------------------------------------------------"
    
    for vmid in $(seq "$start" "$end"); do
        # Check if VM exists
        if ! vm_exists "$vmid"; then
            echo -e "${YELLOW}⊘ VM ${vmid} does not exist, skipping...${NC}"
            ((skipped_count++))
            continue
        fi
        
        # Find the latest snapshot with the prefix
        snapshot=$(find_latest_snapshot "$vmid")
        
        if [ -z "$snapshot" ]; then
            echo -e "${YELLOW}⊘ No snapshot with prefix '${SNAPSHOT_PREFIX}' found for VM ${vmid}, skipping...${NC}"
            ((skipped_count++))
            continue
        fi
        
        # Rollback the VM
        if rollback_vm "$vmid" "$snapshot"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
        
        echo ""
    done
    
    echo ""
done

# Summary
echo "================================================"
echo "Rollback Summary:"
echo "------------------------------------------------"
echo -e "${GREEN}Successfully rolled back: ${success_count} VMs${NC}"
echo -e "${RED}Failed rollbacks: ${failed_count} VMs${NC}"
echo -e "${YELLOW}Skipped: ${skipped_count} VMs${NC}"
echo "Total VMs processed: $((success_count + failed_count + skipped_count))"
echo "================================================"

# Always exit successfully - script completed its run
exit 0
