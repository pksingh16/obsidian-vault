```markdown
# Proxmox CEPH Stretched Cluster Deployment Guide

## Prerequisites

```bash
## All Proxmox Clusters must be synchronized to NTP using Chrony
## Time synchronization is CRITICAL for Ceph cluster stability
apt install chrony -y
systemctl enable --now chrony
chronyc sources -v  # Verify time synchronization
```

## Initial Ceph Configuration

```bash
# Configure CEPH for the first time
# Set separate networks for public (client) and cluster (backend) traffic
pveceph install  # Install Ceph packages
pveceph init --network <public_network> --cluster-network <cluster_network>
```

## Monitor Deployment

```bash
# Create Monitors at each site (OCC, BOCC, Witness)
# Minimum 3 monitors recommended per site for production
pveceph createmon --mon-addr <OCC1_IP>  # On OCC node 1
pveceph createmon --mon-addr <OCC2_IP>  # On OCC node 2
pveceph createmon --mon-addr <BOCC1_IP> # On BOCC node 1
pveceph createmon --mon-addr <BOCC2_IP> # On BOCC node 2
pveceph createmon --mon-addr <WITNESS_IP> # On witness node
```

## Manager Deployment

```bash
# Create Managers with OCC as active
pveceph createmgr --mgr-id 1 --active  # On OCC node
pveceph createmgr --mgr-id 2           # On BOCC node (standby)
pveceph createmgr --mgr-id 3           # On witness node (standby)
```

## CRUSH Map Configuration

```bash
# Get current CRUSH map
ceph osd getcrushmap -o crushmap.bin

# Decompile to human-readable format
crushtool -d crushmap.bin -o crushmap.txt

# Edit crushmap.txt to define:
# 1. Datacenter buckets (occ, bocc, witness)
# 2. Failure domains (rack, host)
# 3. Replication strategy for stretched cluster

# Recompile edited CRUSH map
crushtool -c crushmap.txt -o newcrushmap.bin

# Apply new CRUSH map
ceph osd setcrushmap -i newcrushmap.bin
```

## Monitor Location Configuration

```bash
# Set monitor locations for stretched cluster awareness
ceph mon set_location occ1 datacenter=occ
ceph mon set_location occ2 datacenter=occ
ceph mon set_location bocc1 datacenter=bocc
ceph mon set_location bocc2 datacenter=bocc
ceph mon set_location witness datacenter=witness
```

## Cluster Optimization

```bash
# Set monitor election strategy for stretched clusters
ceph mon set election_strategy connectivity

# Enable stretched cluster mode with custom CRUSH rule
ceph mon enable_stretch_mode stretch_rule datacenter
```

## Complete Cluster Purge (When Needed)

```bash
# WARNING: This will COMPLETELY remove Ceph configuration
systemctl disable --now ceph-mon.target ceph-mgr.target ceph-mds.target ceph-osd.target
killall -9 ceph-mon ceph-mgr ceph-mds
pveceph purge
apt purge ceph-mon ceph-osd ceph-mgr ceph-mds ceph-base ceph-mgr-modules-core -y
rm -rf /etc/systemd/system/ceph* /var/lib/ceph/mon/ /var/lib/ceph/mgr/ /var/lib/ceph/mds/ \
       /etc/pve/priv/ceph.* /etc/ceph/* /etc/pve/ceph.conf
apt autoremove

# Securely wipe OSD disks
for disk in sda sdb sdc sdd sde sdf sdg sdh sdi; do
    echo "Wiping /dev/$disk ..."
    dmsetup remove_all || true
    lvremove -fy $(lvs --noheadings -o lv_path | grep $disk) || true
    vgremove -fy $(pvs --noheadings -o vg_name /dev/$disk 2>/dev/null) || true
    pvremove -fy /dev/$disk || true
    cryptsetup luksClose $(ls /dev/mapper | grep -i $disk) 2>/dev/null || true
    wipefs -a /dev/$disk
    dd if=/dev/zero of=/dev/$disk bs=1M count=100 status=progress
done
```

## Verification Commands

```bash
# Verify cluster health
ceph -s

# Check monitor status
ceph mon stat

# Verify manager status
ceph mgr stat

# Check OSD tree with locations
ceph osd tree
```

## Important Notes

1. **Network Configuration**:
   - Public network: For client traffic (typically 1G/10G)
   - Cluster network: For backend replication (recommended 25G/40G+)

2. **Stretched Cluster Requirements**:
   - Minimum 3 sites (2 data centers + 1 witness)
   - Low latency between sites (<10ms recommended)
   - Identical hardware configuration recommended

3. **Maintenance Tips**:
   - Always drain OSDs before removal
   - Monitor PG states during changes
   - Keep Proxmox and Ceph versions compatible
```
 