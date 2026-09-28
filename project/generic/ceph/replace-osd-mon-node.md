# Replace a Failed OSD + MON Proxmox Node

This runbook applies only to `occ1`, `occ2`, `bocc1`, or `bocc2`. The server runs
Ceph OSDs and one data-site MON participating in quorum. It may host QEMU VMs, and
all VM disks are on shared Ceph storage.

Choose exactly one complete procedure:

- **Procedure A:** replacement keeps the same hostname and IP addresses.
- **Procedure B:** replacement uses a different hostname and IP addresses.

Production uses LACP `bond0`/VLAN-aware `vmbr0` and LACP
`bond1`/VLAN-aware `vmbr1`. The canonical details are in
[Production Network Configuration](ceph-network-configuration.md).

| Host | Mgmt 111 | Corosync 114 | Migration 115 | Ceph public 117 | Ceph cluster 118 | Admin 125 |
| --- | --- | --- | --- | --- | --- | --- |
| `occ1` | `10.50.1.10/26` | `10.50.1.200/26` | `10.50.2.10/25` | `10.50.3.10/25` | `10.50.3.140/25` | `10.50.7.69/26` |
| `occ2` | `10.50.1.11/26` | `10.50.1.201/26` | `10.50.2.11/25` | `10.50.3.11/25` | `10.50.3.141/25` | `10.50.7.70/26` |
| `bocc1` | `10.50.1.20/26` | `10.50.1.203/26` | `10.50.2.13/25` | `10.50.3.20/25` | `10.50.3.150/25` | `10.50.7.72/26` |
| `bocc2` | `10.50.1.21/26` | `10.50.1.204/26` | `10.50.2.14/25` | `10.50.3.21/25` | `10.50.3.151/25` | `10.50.7.73/26` |

## Procedure A: Same Hostname and IP Addresses

### A1. Define the reused identity

Set these values in every shell where they are used. `SITE` must be `occ` or `bocc`.

```bash
OLD_NODE=occ2
NEW_NODE=occ2
RECOVERY_NODE=occ1
SITE=occ
PVE_JOIN_IP=10.50.1.10
MGMT_IP='<old_management_ip>'
COROSYNC_IP='<old_corosync_ip>'
MIGRATION_IP='<old_migration_ip>'
CEPH_PUBLIC_IP='<old_ceph_public_ip>'
CEPH_CLUSTER_IP='<old_ceph_cluster_ip>'
ADMIN_IP='<old_admin_ip>'

printf 'OLD=%s NEW=%s RECOVERY=%s SITE=%s CEPH_PUBLIC=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$RECOVERY_NODE" "$SITE" "$CEPH_PUBLIC_IP"
```

`OLD_NODE` and `NEW_NODE` must match. Record all reused DNS, BMC, bridge, bond, VLAN,
MTU, routing, Corosync-link, Ceph-network, switch-port, and hardware-mapping values.

### A2. Fence the failed server

Power off or fence the failed hardware so it cannot reuse its old Corosync identity,
MON identity, hostname, or IP addresses.

> [!DANGER]
> Do not continue without confirmed fencing. Never start the old and replacement
> installations concurrently.

### A3. Verify surviving Proxmox and Ceph quorum

These read-only commands establish whether losing this data-site MON still leaves a
safe majority and whether PG/client state permits recovery work.

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm nodes
ha-manager status
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
```

Continue only if Proxmox has quorum, the remaining Ceph MONs have quorum, client I/O
works, no second server/site has failed, and no PG is `inactive`, `incomplete`,
`stale`, or `unknown`. Do not remove the failed MON if that would lose MON majority.

### A4. Capture VM policy and Ceph topology

This creates a protected evidence bundle before changing VM ownership, MON membership,
OSDs, or Proxmox membership. Copy it to off-cluster storage afterward.

```bash
# Run on RECOVERY_NODE.
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/replace-$OLD_NODE-$STAMP
install -d -m 0700 "$BACKUP"/{pve,ceph,vms}

pvecm status > "$BACKUP/pve/pvecm-status.txt"
pvecm nodes > "$BACKUP/pve/pvecm-nodes.txt"
pveversion -v > "$BACKUP/pve/pveversion.txt"
ha-manager status > "$BACKUP/pve/ha-status.txt"
ha-manager config > "$BACKUP/pve/ha-config.txt"
pvesh get /cluster/resources --type vm --output-format json-pretty > "$BACKUP/pve/vms.json"
pvesh get /cluster/ha/groups --output-format json-pretty > "$BACKUP/pve/ha-groups.json" 2>&1 || true
pvesh get /cluster/ha/resources --output-format json-pretty > "$BACKUP/pve/ha-resources.json" 2>&1 || true
pvesh get /cluster/backup --output-format json-pretty > "$BACKUP/pve/backup-jobs.json" 2>&1 || true
pvesh get /cluster/firewall/aliases --output-format json-pretty > "$BACKUP/pve/firewall-aliases.json" 2>&1 || true
pvesh get /cluster/mapping/pci --output-format json-pretty > "$BACKUP/pve/pci-mappings.json" 2>&1 || true
pvesh get /cluster/mapping/usb --output-format json-pretty > "$BACKUP/pve/usb-mappings.json" 2>&1 || true
pvesh get /storage --output-format json-pretty > "$BACKUP/pve/storage.json"
cp -a /etc/pve/datacenter.cfg /etc/pve/storage.cfg /etc/pve/corosync.conf "$BACKUP/pve/"
cp -a /etc/pve/ha "$BACKUP/pve/ha-directory"
cp -a "/etc/pve/nodes/$OLD_NODE" "$BACKUP/pve/old-node-directory"
cp -a /etc/pve/mapping "$BACKUP/pve/mapping-directory" 2>/dev/null || true
cp -a /etc/pve/firewall "$BACKUP/pve/firewall-directory" 2>/dev/null || true

find "/etc/pve/nodes/$OLD_NODE/qemu-server" -maxdepth 1 -type f -print \
  > "$BACKUP/vms/config-files.txt" 2>/dev/null
awk -F/ '/qemu-server\/[0-9]+\.conf$/ {gsub(/\.conf/,"",$NF); print $NF}' \
  "$BACKUP/vms/config-files.txt" > "$BACKUP/vms/vm-list.txt"
while read -r VMID; do
  qm config "$VMID" > "$BACKUP/vms/qm-$VMID.conf"
  qm status "$VMID" > "$BACKUP/vms/qm-$VMID.status"
done < "$BACKUP/vms/vm-list.txt"
grep -RnwE "$OLD_NODE|affinity|group|restricted|nodes[=:]" \
  /etc/pve/ha /etc/pve/datacenter.cfg /etc/pve/storage.cfg /etc/pve/jobs.cfg \
  2>/dev/null > "$BACKUP/pve/node-policy-references.txt" || true

ceph -s > "$BACKUP/ceph/status.txt"
ceph health detail > "$BACKUP/ceph/health.txt"
ceph mon dump -f json-pretty > "$BACKUP/ceph/monmap.json"
ceph quorum_status -f json-pretty > "$BACKUP/ceph/quorum.json"
ceph osd tree > "$BACKUP/ceph/osd-tree.txt"
ceph osd metadata -f json-pretty > "$BACKUP/ceph/osd-metadata.json"
ceph osd dump > "$BACKUP/ceph/osd-dump.txt"
ceph mon getmap -o "$BACKUP/ceph/monmap.bin"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"
```

### A5. Recover VMs onto surviving nodes

VM disks remain on shared Ceph. The following inventory prevents duplicate VM
configuration or execution:

```bash
# Run on RECOVERY_NODE.
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

Let HA recover managed VMs. For each verified non-HA VM still configured only under
the failed node, this moves its configuration, not its shared Ceph disks:

```bash
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

Validate application health and stop if any VM disk references node-local storage.

### A6. Remove the failed MON from the committed monmap

This removes only the unavailable MON identity. It does not remove the Proxmox node
or its OSDs. Confirm the remaining MON majority immediately before running it.

```bash
# Run on RECOVERY_NODE.
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph mon remove "$OLD_NODE"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
```

Do not continue until the committed monmap no longer contains the old name or MON IP
and the remaining MONs have stable quorum.

### A7. Remove each permanently lost OSD

For one OSD whose metadata identifies `OLD_NODE`, marking it out starts recovery:

```bash
# Run on RECOVERY_NODE, one OSD at a time.
OSD_ID=<old_osd_id>
ceph osd find "$OSD_ID"
ceph osd metadata "$OSD_ID" -f json-pretty
ceph osd out "$OSD_ID"
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

After recovery settles, verify the OSD is safe to destroy:

```bash
ceph osd safe-to-destroy "$OSD_ID"
```

> [!DANGER]
> The purge removes the OSD ID, Cephx entry, and CRUSH entry. Run it only after
> `safe-to-destroy` succeeds.

```bash
ceph osd purge "$OSD_ID" --yes-i-really-mean-it
ceph osd tree
```

Repeat for each failed OSD. Retain the empty same-name CRUSH host bucket.

### A8. Remove stale Proxmox membership

This removes the fenced server from Corosync membership:

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

The next block removes the stale same-name node directory after refusing mismatched
variables. Confirm VM recovery and the off-cluster evidence copy first.

```bash
test -n "$OLD_NODE" && test "$OLD_NODE" = "$NEW_NODE" || {
  echo 'STOP: not a same-name replacement'
  false
}
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### A9. Build and join the replacement

Install the same Proxmox VE/kernel/Ceph versions and repositories. Configure the old
hostname and all old management, Corosync, migration, Ceph public, Ceph cluster, and
admin IPs. Update switch port security, LACP, DHCP, ARP inspection, DNS/IPAM,
monitoring, BMC, and any MAC-dependent controls before enabling reused addresses.

These commands verify identity, time, network, and versions without modifying the
cluster:

```bash
# Run on the replacement.
hostnamectl hostname "$NEW_NODE"
hostname -s
getent hosts "$NEW_NODE"
ip -br address
ip route
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
bridge vlan show dev vmbr0
bridge vlan show dev vmbr1
for EXPECTED_IP in "$MGMT_IP" "$COROSYNC_IP" "$MIGRATION_IP" \
  "$CEPH_PUBLIC_IP" "$CEPH_CLUSTER_IP" "$ADMIN_IP"; do
  ip -br address | grep -F "${EXPECTED_IP%/*}"
done
timedatectl status
chronyc tracking
chronyc sources -v
pveversion -v
apt-cache policy ceph-common ceph-mon ceph-osd
```

After comparing with a healthy peer, this joins the replacement to Proxmox and obtains
the live shared `/etc/pve` configuration:

```bash
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`, restore old daemon keys, or copy old `/var/lib/ceph`.
Replacement MON and OSD creation obtains or generates current Cephx credentials.

### A10. Recreate the data-site MON

Stretch mode rejects a new MON without a location. This creates a local systemd
override so the MON announces `datacenter=occ` or `datacenter=bocc` on first start:

```bash
# Run on the replacement. Replace <occ-or-bocc> with SITE's literal value.
install -d -m 0755 "/etc/systemd/system/ceph-mon@$NEW_NODE.service.d"
nano "/etc/systemd/system/ceph-mon@$NEW_NODE.service.d/override.conf"
```

Save exactly this, using the correct literal site:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=<occ-or-bocc>
```

The next commands reload systemd and verify the effective command before MON creation:

```bash
systemctl daemon-reload
systemctl cat "ceph-mon@$NEW_NODE.service"
systemctl show "ceph-mon@$NEW_NODE.service" -p ExecStart
```

Confirm the effective `ExecStart` contains the correct site. This command then creates
and starts the MON at the reused public IP:

```bash
pveceph mon create --mon-address "$CEPH_PUBLIC_IP"
```

From `RECOVERY_NODE`, verify the MON is committed at the correct site and in quorum:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

Do not create OSDs until all five intended MONs are in stable quorum.

### A11. Create replacement OSDs

This read-only disk inventory prevents selecting the wrong device:

```bash
# Run on the replacement.
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Confirm the retained host bucket remains below the correct site:

```bash
# Run on RECOVERY_NODE.
ceph osd crush tree
```

Each command destroys the selected blank disk and creates a new OSD/Cephx identity:

```bash
# Run on the replacement, once per verified disk.
pveceph osd create /dev/<verified_blank_disk>
```

After each creation, wait for correct placement and `active+clean` PGs:

```bash
# Run on RECOVERY_NODE.
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
ceph osd tree
ceph osd crush tree
```

### A12. Restore VM policy and validate full recovery

Because the hostname is unchanged, policy references usually become valid again.
These comparisons show drift without overwriting live cluster configuration:

```bash
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Return VMs deliberately and verify HA/affinity, mappings, backup inclusion, QEMU guest
agent, networking, disks, and application health. Final checks must show five MONs in
quorum, replacement OSDs under the correct site, and all PGs `active+clean`:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ha-manager status
```

Securely erase or destroy all failed-server disks and never reconnect its old system.

---

## Procedure B: Different Hostname and IP Addresses

### B1. Define the old and new identities

Set these values in every shell. `SITE` must remain the failed node's original data
site so the stretch topology returns to two MONs at each data site.

```bash
OLD_NODE=occ2
NEW_NODE=occ4
RECOVERY_NODE=occ1
SITE=occ
PVE_JOIN_IP=10.50.1.10
NEW_MGMT_IP='<new_management_ip>'
NEW_COROSYNC_IP='<new_corosync_ip>'
NEW_MIGRATION_IP='<new_migration_ip>'
NEW_CEPH_PUBLIC_IP='<new_ceph_public_ip>'
NEW_CEPH_CLUSTER_IP='<new_ceph_cluster_ip>'
NEW_ADMIN_IP='<new_admin_ip>'

printf 'OLD=%s NEW=%s RECOVERY=%s SITE=%s NEW_MON_IP=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$RECOVERY_NODE" "$SITE" "$NEW_CEPH_PUBLIC_IP"
```

### B2. Fence and check surviving quorum

Permanently fence the failed server. These commands then verify that the remaining
Proxmox members and four MONs can support the replacement:

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm nodes
ha-manager status
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
```

Stop if either quorum is absent, another server/site has failed, client I/O fails, or
any PG is `inactive`, `incomplete`, `stale`, or `unknown`.

### B3. Capture VM policy and Ceph topology

This bundle is the translation baseline from `OLD_NODE` to `NEW_NODE`. Copy it to
secure off-cluster storage before removal.

```bash
# Run on RECOVERY_NODE.
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/replace-$OLD_NODE-with-$NEW_NODE-$STAMP
install -d -m 0700 "$BACKUP"/{pve,ceph,vms}

pvecm status > "$BACKUP/pve/pvecm-status.txt"
pvecm nodes > "$BACKUP/pve/pvecm-nodes.txt"
pveversion -v > "$BACKUP/pve/pveversion.txt"
ha-manager status > "$BACKUP/pve/ha-status.txt"
ha-manager config > "$BACKUP/pve/ha-config.txt"
pvesh get /cluster/resources --type vm --output-format json-pretty > "$BACKUP/pve/vms.json"
pvesh get /cluster/ha/groups --output-format json-pretty > "$BACKUP/pve/ha-groups.json" 2>&1 || true
pvesh get /cluster/ha/resources --output-format json-pretty > "$BACKUP/pve/ha-resources.json" 2>&1 || true
pvesh get /cluster/backup --output-format json-pretty > "$BACKUP/pve/backup-jobs.json" 2>&1 || true
pvesh get /cluster/firewall/aliases --output-format json-pretty > "$BACKUP/pve/firewall-aliases.json" 2>&1 || true
pvesh get /cluster/mapping/pci --output-format json-pretty > "$BACKUP/pve/pci-mappings.json" 2>&1 || true
pvesh get /cluster/mapping/usb --output-format json-pretty > "$BACKUP/pve/usb-mappings.json" 2>&1 || true
pvesh get /storage --output-format json-pretty > "$BACKUP/pve/storage.json"
cp -a /etc/pve/datacenter.cfg /etc/pve/storage.cfg /etc/pve/corosync.conf "$BACKUP/pve/"
cp -a /etc/pve/ha "$BACKUP/pve/ha-directory"
cp -a "/etc/pve/nodes/$OLD_NODE" "$BACKUP/pve/old-node-directory"
cp -a /etc/pve/mapping "$BACKUP/pve/mapping-directory" 2>/dev/null || true
cp -a /etc/pve/firewall "$BACKUP/pve/firewall-directory" 2>/dev/null || true

find "/etc/pve/nodes/$OLD_NODE/qemu-server" -maxdepth 1 -type f -print \
  > "$BACKUP/vms/config-files.txt" 2>/dev/null
awk -F/ '/qemu-server\/[0-9]+\.conf$/ {gsub(/\.conf/,"",$NF); print $NF}' \
  "$BACKUP/vms/config-files.txt" > "$BACKUP/vms/vm-list.txt"
while read -r VMID; do
  qm config "$VMID" > "$BACKUP/vms/qm-$VMID.conf"
  qm status "$VMID" > "$BACKUP/vms/qm-$VMID.status"
done < "$BACKUP/vms/vm-list.txt"
grep -RnwE "$OLD_NODE|affinity|group|restricted|nodes[=:]" \
  /etc/pve/ha /etc/pve/datacenter.cfg /etc/pve/storage.cfg /etc/pve/jobs.cfg \
  2>/dev/null > "$BACKUP/pve/node-policy-references.txt" || true

ceph -s > "$BACKUP/ceph/status.txt"
ceph health detail > "$BACKUP/ceph/health.txt"
ceph mon dump -f json-pretty > "$BACKUP/ceph/monmap.json"
ceph quorum_status -f json-pretty > "$BACKUP/ceph/quorum.json"
ceph osd tree > "$BACKUP/ceph/osd-tree.txt"
ceph osd metadata -f json-pretty > "$BACKUP/ceph/osd-metadata.json"
ceph osd dump > "$BACKUP/ceph/osd-dump.txt"
ceph mon getmap -o "$BACKUP/ceph/monmap.bin"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"
```

### B4. Recover VMs onto surviving nodes

The disks remain on shared Ceph. First ensure every VMID has one configuration and is
not running twice:

```bash
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

Let HA recover managed VMs. For each verified non-HA VM still under `OLD_NODE`, move
only its configuration and start it from the shared disks:

```bash
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

### B5. Remove the failed MON

This changes only MON membership. Verify majority first, remove `OLD_NODE`, then
confirm the old name/address is absent and quorum remains stable:

```bash
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph mon remove "$OLD_NODE"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
```

### B6. Remove old OSDs and CRUSH host

For each old OSD, marking it out starts recovery:

```bash
OSD_ID=<old_osd_id>
ceph osd find "$OSD_ID"
ceph osd metadata "$OSD_ID" -f json-pretty
ceph osd out "$OSD_ID"
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

After recovery, this check must succeed before purge:

```bash
ceph osd safe-to-destroy "$OSD_ID"
```

> [!DANGER]
> Purge permanently removes that OSD's cluster records. Run it only after the safety
> check succeeds.

```bash
ceph osd purge "$OSD_ID" --yes-i-really-mean-it
```

Repeat per OSD. Once the old host bucket is empty, remove it because the replacement
uses a different hostname:

```bash
ceph osd crush tree
ceph osd crush remove "$OLD_NODE"
ceph osd crush tree
```

### B7. Remove old Proxmox membership and stale files

This removes the fenced node from Corosync:

```bash
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

After confirming all VM configurations are recovered and the bundle is off-cluster,
inspect and remove only the stale old-node directory:

```bash
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### B8. Build and join the new identity

Install matching Proxmox/Ceph versions and configure new DNS/IPAM, BMC, switch ports,
bonds, bridges, VLANs, MTU, routes, firewall, VLAN 114 Corosync, and Ceph networks.

These checks are read-only and must match the intended design and healthy peers:

```bash
# Run on the replacement.
hostnamectl hostname "$NEW_NODE"
hostname -s
getent hosts "$NEW_NODE"
ip -br address
ip route
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
bridge vlan show dev vmbr0
bridge vlan show dev vmbr1
for EXPECTED_IP in "$NEW_MGMT_IP" "$NEW_COROSYNC_IP" "$NEW_MIGRATION_IP" \
  "$NEW_CEPH_PUBLIC_IP" "$NEW_CEPH_CLUSTER_IP" "$NEW_ADMIN_IP"; do
  ip -br address | grep -F "${EXPECTED_IP%/*}"
done
timedatectl status
chronyc tracking
chronyc sources -v
pveversion -v
apt-cache policy ceph-common ceph-mon ceph-osd
```

Join the existing Proxmox cluster and verify shared Ceph access:

```bash
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`, restore old daemon keys, or copy old `/var/lib/ceph`.

### B9. Create the new data-site MON

The override below adds the mandatory stretch location on first start. Replace the
placeholder with literal `occ` or `bocc`:

```bash
install -d -m 0755 "/etc/systemd/system/ceph-mon@$NEW_NODE.service.d"
nano "/etc/systemd/system/ceph-mon@$NEW_NODE.service.d/override.conf"
```

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=<occ-or-bocc>
```

Reload and inspect the effective service before creation:

```bash
systemctl daemon-reload
systemctl cat "ceph-mon@$NEW_NODE.service"
systemctl show "ceph-mon@$NEW_NODE.service" -p ExecStart
```

Create the MON at the new public IP:

```bash
pveceph mon create --mon-address "$NEW_CEPH_PUBLIC_IP"
```

Verify from `RECOVERY_NODE` that the new MON is committed at `SITE`, appears in
`quorum_names`, and restores the intended five-MON layout:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

### B10. Create and place replacement OSDs

Inspect disks before destructive creation:

```bash
# Run on the replacement.
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Each command destroys one selected disk and creates a new OSD/Cephx identity:

```bash
pveceph osd create /dev/<verified_blank_disk>
```

Move the new host below the original data site, then monitor recovery:

```bash
# Run on RECOVERY_NODE.
ceph osd crush move "$NEW_NODE" datacenter="$SITE"
ceph osd crush tree
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

Wait for `active+clean` before adding the next OSD when recovery load is material.

### B11. Translate policy and validate full recovery

Compare rather than overwrite live policy:

```bash
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
grep -Rnw "$OLD_NODE" /etc/pve/ha /etc/pve/*.cfg 2>/dev/null || true
```

Replace `OLD_NODE` references through supported Proxmox interfaces in HA/affinity,
storage restrictions, backup jobs, mappings, firewall/SDN, monitoring, DNS/IPAM,
automation, and allowlists. Return VMs deliberately and validate each application.

Final checks must show `NEW_NODE`, no `OLD_NODE`, exactly five MONs in quorum, the new
MON at the correct site, replacement OSDs under that site, and clean PGs:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Securely erase or destroy all failed-server disks and never reconnect its old system.

## Emergency Stop Conditions

For either procedure, stop all removals if Proxmox or Ceph quorum changes unexpectedly,
another host/site fails, a PG becomes `inactive`/`incomplete`/`stale`/`unknown`, client
I/O fails, capacity approaches `backfillfull`, or the replacement has clock skew,
wrong versions/location, duplicate identity, or unstable networking.
