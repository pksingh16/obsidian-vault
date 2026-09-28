# Replace a Failed Witness/Quorum MON-Only Node

This runbook applies only to the stretch tiebreaker Proxmox server. Its only Ceph
daemon is one MON at logical location `datacenter=witness`; it has no OSDs. It may
host QEMU VMs, and every VM disk is on shared Ceph storage.

Choose exactly one complete procedure:

- **Procedure A:** replacement keeps the same hostname, MON ID, and IP addresses.
- **Procedure B:** replacement uses a different hostname, MON ID, and IP addresses.

Never create a `witness` bucket in the OSD CRUSH tree and never create OSDs on this
server.

Production `quorum` uses LACP `bond0`/VLAN-aware `vmbr0` for all active host networks.
It has no Storage-switch path or VLAN 118. Empty `bond1`/`vmbr1` definitions may be
retained by the host template, but they must carry no IP or Ceph backend traffic. See
[Production Network Configuration](ceph-network-configuration.md).

| Host | Mgmt 111 | Corosync 114 | Migration 115 | Ceph public 117 | Ceph cluster 118 | Admin 125 |
| --- | --- | --- | --- | --- | --- | --- |
| `quorum` | `10.50.1.31/26` | `10.50.1.207/26` | `10.50.2.31/25` | `10.50.3.31/25` | Not configured | `10.50.7.118/26` |

## Procedure A: Same Hostname, MON ID, and IP Addresses

### A1. Define the reused identity

Set these variables in every shell where they are used. The MON ID equals the short
hostname and does not include the `mon.` prefix.

```bash
OLD_NODE=quorum
NEW_NODE=quorum
OLD_MON=quorum
NEW_MON=quorum
RECOVERY_NODE=occ1
PVE_JOIN_IP=10.50.1.10
MGMT_IP='<old_management_ip>'
COROSYNC_IP='<old_corosync_ip>'
MIGRATION_IP='<old_migration_ip>'
CEPH_PUBLIC_IP='<old_ceph_public_ip>'
ADMIN_IP='<old_admin_ip>'
TEMP_NODE=quorum-temp
TEMP_MON=quorum-temp
TEMP_MGMT_IP='<temporary_management_ip>'
TEMP_COROSYNC_IP='<temporary_corosync_ip>'
TEMP_MIGRATION_IP='<temporary_migration_ip>'
TEMP_CEPH_PUBLIC_IP='<temporary_ceph_public_ip>'
TEMP_ADMIN_IP='<temporary_admin_ip>'

printf 'OLD=%s NEW=%s FINAL_MON=%s TEMP_MON=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$NEW_MON" "$TEMP_MON"
```

The old/final node and MON identities must match. `TEMP_NODE`/`TEMP_MON` and all
temporary IPs must be unique and unused.

### A2. Fence the failed server

Power off, disconnect, or fence the old server so it cannot boot with the reused
hostname, Corosync identity, MON ID, or addresses.

> [!DANGER]
> Ceph refuses to remove the active stretch tiebreaker. Exact identity reuse therefore
> requires a temporary Proxmox node or VM with a unique hostname/IP and a temporary
> tiebreaker MON. Do not proceed without that temporary host. Never place its MON at a
> data-site location or create OSDs on it.

### A3. Verify all four data-site MONs and PGs

These commands do not change state. They prove that `occ1`, `occ2`, `bocc1`, and
`bocc2` are in quorum before the failed tiebreaker entry is removed.

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

Continue only if all four data-site MONs are in `quorum_names`, all PGs are
`active+clean`, client I/O works, and no other server/site has failed.

### A4. Capture VM policy and cluster evidence

This creates a protected bundle before moving VM configurations or deleting the node
and MON identities. Copy it to off-cluster storage afterward.

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
ceph mon getmap -o "$BACKUP/ceph/monmap.bin"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"
```

### A5. Recover VMs onto surviving nodes

The VM disks remain on shared Ceph. First verify each VMID has one configuration and
is not running twice:

```bash
# Run on RECOVERY_NODE.
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

Let HA recover managed VMs. For each verified non-HA VM still under the failed node,
this moves only its configuration to a surviving node and starts it using existing
Ceph-backed disks:

```bash
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

Validate each application and stop if any disk references node-local storage.

### A6. Build a temporary Proxmox tiebreaker node

Install the same Proxmox VE/kernel/Ceph versions on a temporary node or VM. Configure
its unique hostname, management, Corosync, and Ceph public addresses. It needs no
Ceph cluster network or OSD disks.

These checks verify its unique identity, clock, and package versions before joining:

```bash
# Run on TEMP_NODE.
hostnamectl hostname "$TEMP_NODE"
hostname -s
getent hosts "$TEMP_NODE"
ip -br address
ip route
cat /proc/net/bonding/bond0
bridge vlan show dev vmbr0
! ip link show vmbr1.118 >/dev/null 2>&1
for EXPECTED_IP in "$TEMP_MGMT_IP" "$TEMP_COROSYNC_IP" "$TEMP_MIGRATION_IP" \
  "$TEMP_CEPH_PUBLIC_IP" "$TEMP_ADMIN_IP"; do
  ip -br address | grep -F "${EXPECTED_IP%/*}"
done
timedatectl status
chronyc tracking
chronyc sources -v
pveversion -v
apt-cache policy ceph-common ceph-mon
```

After comparing versions with a healthy member, join the temporary node to Proxmox:

```bash
# Run on TEMP_NODE.
pvecm add "$PVE_JOIN_IP"
pvecm status
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`.

### A7. Create and select the temporary tiebreaker MON

The override below supplies the mandatory third-site location on the temporary MON's
first start. It does not create an OSD CRUSH bucket.

```bash
# Run on TEMP_NODE.
pveceph install
install -d -m 0755 "/etc/systemd/system/ceph-mon@$TEMP_MON.service.d"
nano "/etc/systemd/system/ceph-mon@$TEMP_MON.service.d/override.conf"
```

Save exactly:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=witness
```

Reload systemd, verify the location argument, then create the temporary MON:

```bash
systemctl daemon-reload
systemctl show "ceph-mon@$TEMP_MON.service" -p ExecStart
pveceph mon create --mon-address "$TEMP_CEPH_PUBLIC_IP"
```

From `RECOVERY_NODE`, first verify `TEMP_MON` is committed at `datacenter=witness`
and in quorum. Then switch the tiebreaker designation to it:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph mon set_new_tiebreaker "$TEMP_MON"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
```

Do not continue until `tiebreaker_mon` and `disallowed_leaders` identify `TEMP_MON`,
it is in quorum, and all four data-site MONs remain in quorum.

### A8. Remove the failed final MON identity

Now that it is no longer the active tiebreaker, this removes the failed old MON from
the committed map and frees its name/IP for exact reuse:

```bash
# Run on RECOVERY_NODE.
ceph mon remove "$OLD_MON"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
```

Confirm the old name/address is absent and `TEMP_MON` remains the tiebreaker.

### A9. Remove old Proxmox membership and stale files

This removes the fenced server from Corosync membership:

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

The stale directory can block same-name join. The next block refuses mismatched
identities, displays remaining files, then removes only the old Proxmox node metadata.
Run it only after VM recovery and off-cluster backup.

```bash
test -n "$OLD_NODE" && test "$OLD_NODE" = "$NEW_NODE" || {
  echo 'STOP: not a same-name replacement'
  false
}
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### A10. Build and join the final replacement

Install matching Proxmox VE/kernel/Ceph versions. Configure the reused hostname and
management, Corosync, migration, Ceph public, and admin IPs. This MON-only server
must not receive VLAN 118, a Ceph cluster/replication interface, or OSD disks.

Before enabling reused addresses, update switch security, LACP, DHCP, ARP inspection,
DNS/IPAM, monitoring, BMC, and MAC-dependent controls. Clear stale neighbor state
through the owning network platform.

These checks are read-only:

```bash
# Run on the replacement.
hostnamectl hostname "$NEW_NODE"
hostname -s
getent hosts "$NEW_NODE"
ip -br address
ip route
cat /proc/net/bonding/bond0
bridge vlan show dev vmbr0
! ip link show vmbr1.118 >/dev/null 2>&1
for EXPECTED_IP in "$MGMT_IP" "$COROSYNC_IP" "$MIGRATION_IP" \
  "$CEPH_PUBLIC_IP" "$ADMIN_IP"; do
  ip -br address | grep -F "${EXPECTED_IP%/*}"
done
timedatectl status
chronyc tracking
chronyc sources -v
pveversion -v
apt-cache policy ceph-common ceph-mon
```

After comparing with healthy peers, join Proxmox and verify access to shared Ceph
configuration:

```bash
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`, restore old MON keys, or copy old `/var/lib/ceph`. MON
creation initializes current credentials and monmap data from the live cluster.

### A11. Recreate the final tiebreaker candidate MON

Stretch mode rejects a new MON without a location. This creates an instance override
that announces the logical third location; it does not create an OSD CRUSH bucket.

```bash
# Run on the replacement.
pveceph install
install -d -m 0755 "/etc/systemd/system/ceph-mon@$NEW_MON.service.d"
nano "/etc/systemd/system/ceph-mon@$NEW_MON.service.d/override.conf"
```

Save exactly:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=witness
```

Reload systemd and verify the effective start command before creation:

```bash
systemctl daemon-reload
systemctl cat "ceph-mon@$NEW_MON.service"
systemctl show "ceph-mon@$NEW_MON.service" -p ExecStart
```

Confirm the location argument is present. Then create and start the replacement MON
at the reused public IP:

```bash
pveceph mon create --mon-address "$CEPH_PUBLIC_IP"
```

If creation initialized the store but service start failed, do not rerun creation or
delete the store. Inspect it with:

```bash
systemctl status "ceph-mon@$NEW_MON.service" --no-pager -l
journalctl -u "ceph-mon@$NEW_MON.service" -b -o short-iso-precise --no-pager
tail -n 200 "/var/log/ceph/ceph-mon.$NEW_MON.log"
```

### A12. Switch from the temporary MON to the final MON

These commands verify the recreated final MON is committed with
`datacenter=witness` and in quorum. The switch command uses the ID without a `mon.`
prefix and moves the tiebreaker/disallowed-leader state away from `TEMP_MON`.

```bash
# Run on RECOVERY_NODE.
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph mon set_new_tiebreaker "$NEW_MON"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

Do not continue until the four data-site MONs plus `NEW_MON` and `TEMP_MON` are in
quorum, `tiebreaker_mon` and `disallowed_leaders` identify `NEW_MON`, its location is
`datacenter=witness`, and no clock-skew warning exists. There are temporarily six MON
entries until the temporary MON is removed.

### A13. Remove the temporary MON and Proxmox node

The following destroys the temporary MON locally after it is no longer tiebreaker,
then verifies that the final five-MON map remains healthy:

```bash
# Run on TEMP_NODE.
pveceph mon destroy "$TEMP_MON"
```

```bash
# Run on RECOVERY_NODE.
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

After confirming the temporary host owns no VM or other service, fence/power it off
and remove its Proxmox membership:

```bash
# Run on RECOVERY_NODE.
pvecm delnode "$TEMP_NODE"
pvecm status
pvecm nodes
```

### A14. Restore VM policy and finish

The same hostname normally reactivates node-based HA/affinity and storage policy.
Compare live state rather than overwriting it:

```bash
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Return VMs deliberately and verify HA/affinity, mappings, backup inclusion, disks,
QEMU guest agent, networking, and application health. The final checks must show the
replacement in Proxmox quorum and the healthy five-MON stretch topology:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
ha-manager status
```

Securely erase or destroy the old system disk and never reconnect that installation.

---

## Procedure B: Different Hostname, MON ID, and IP Addresses

### B1. Define old and new identities

Set these values in every shell. MON IDs are short names without `mon.` prefixes.

```bash
OLD_NODE=witness
NEW_NODE=quorum
OLD_MON=witness
NEW_MON=quorum
RECOVERY_NODE=occ1
PVE_JOIN_IP=10.50.1.10
NEW_MGMT_IP='<new_management_ip>'
NEW_COROSYNC_IP='<new_corosync_ip>'
NEW_MIGRATION_IP='<new_migration_ip>'
NEW_CEPH_PUBLIC_IP='<new_ceph_public_ip>'
NEW_ADMIN_IP='<new_admin_ip>'

printf 'OLD_NODE=%s NEW_NODE=%s OLD_MON=%s NEW_MON=%s NEW_MON_IP=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$OLD_MON" "$NEW_MON" "$NEW_CEPH_PUBLIC_IP"
```

### B2. Fence and verify surviving cluster health

Permanently fence the failed server. These read-only checks verify all four data-site
MONs and the surviving Proxmox cluster before adding the new identity:

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

Continue only if all four data-site MONs are in quorum, PGs are `active+clean`, client
I/O works, and no second server/site has failed.

### B3. Capture VM policy and cluster evidence

This protected bundle records all old hostname/IP references and VM allocation for
translation to the new identity. Copy it off-cluster before continuing.

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
ceph mon getmap -o "$BACKUP/ceph/monmap.bin"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"
```

### B4. Recover VMs onto surviving nodes

The VM disks remain on shared Ceph. Inspect HA recovery and duplicate VMIDs first:

```bash
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

Let HA recover managed VMs. For each verified non-HA VM still under `OLD_NODE`, move
only its configuration to `RECOVERY_NODE` and start it using shared Ceph disks:

```bash
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

### B5. Build and join the replacement Proxmox node

A new identity can join before the old Proxmox membership is removed. Install matching
Proxmox VE/kernel/Ceph versions and configure new DNS/IPAM, BMC, switch ports, bonds,
bridges, VLANs, MTU, routes, firewall, Corosync, and Ceph public networking. Do not
configure a Ceph cluster network or OSD disks on the witness.

These checks are read-only:

```bash
# Run on the replacement.
hostnamectl hostname "$NEW_NODE"
hostname -s
getent hosts "$NEW_NODE"
ip -br address
ip route
cat /proc/net/bonding/bond0
bridge vlan show dev vmbr0
! ip link show vmbr1.118 >/dev/null 2>&1
for EXPECTED_IP in "$NEW_MGMT_IP" "$NEW_COROSYNC_IP" "$NEW_MIGRATION_IP" \
  "$NEW_CEPH_PUBLIC_IP" "$NEW_ADMIN_IP"; do
  ip -br address | grep -F "${EXPECTED_IP%/*}"
done
timedatectl status
chronyc tracking
chronyc sources -v
pveversion -v
apt-cache policy ceph-common ceph-mon
```

Join Proxmox and verify the live shared configuration:

```bash
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`, restore old MON keys, or copy old `/var/lib/ceph`.

### B6. Create the new tiebreaker candidate MON

Stretch mode requires a location on first start. This override announces the logical
witness location without adding an OSD CRUSH bucket:

```bash
# Run on the replacement.
pveceph install
install -d -m 0755 "/etc/systemd/system/ceph-mon@$NEW_MON.service.d"
nano "/etc/systemd/system/ceph-mon@$NEW_MON.service.d/override.conf"
```

Save exactly:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=witness
```

Reload and verify the effective service before creation:

```bash
systemctl daemon-reload
systemctl cat "ceph-mon@$NEW_MON.service"
systemctl show "ceph-mon@$NEW_MON.service" -p ExecStart
```

Create the new MON at its new public IP:

```bash
pveceph mon create --mon-address "$NEW_CEPH_PUBLIC_IP"
```

From `RECOVERY_NODE`, confirm it is committed with `datacenter=witness` and appears in
`quorum_names` before switching:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

A temporary nonexistent-CRUSH-location warning for `NEW_MON` is expected because only
the current tiebreaker is exempt. Do not create a witness CRUSH bucket.

### B7. Switch the tiebreaker and remove the failed MON

This command changes the tiebreaker designation to `NEW_MON`; the argument must not
include a `mon.` prefix:

```bash
# Run on RECOVERY_NODE.
ceph mon set_new_tiebreaker "$NEW_MON"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
```

Confirm `tiebreaker_mon` and `disallowed_leaders` identify `NEW_MON`, it remains in
quorum, all four data-site MONs remain in quorum, and no clock skew exists. The
nonexistent-location warning may now refer to the old MON.

The next command removes only the failed old MON after the successful switch:

```bash
ceph mon remove "$OLD_MON"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

Expected result: exactly five MONs and no nonexistent-location warning.

### B8. Remove old Proxmox membership and stale files

After MON replacement and VM recovery, this removes the fenced old node from Corosync:

```bash
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

Inspect the old node directory, confirm its VM configurations are recovered and the
bundle is off-cluster, then remove only that stale metadata:

```bash
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### B9. Translate policy and return VMs

Compare live policy with the evidence bundle; do not overwrite cluster-wide files:

```bash
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
grep -Rnw "$OLD_NODE" /etc/pve/ha /etc/pve/*.cfg 2>/dev/null || true
```

Replace old hostname/IP references through supported Proxmox interfaces in HA and
affinity rules, storage restrictions, backup jobs, mappings, firewall/SDN, monitoring,
DNS/IPAM, automation, and allowlists. Return VMs deliberately and validate each VM's
HA state, shared disks, networking, QEMU guest agent, application, and backups.

### B10. Final validation

These commands must show `NEW_NODE` in Proxmox quorum, no `OLD_NODE`, five MONs in
quorum, `NEW_MON` as tiebreaker/disallowed leader at `datacenter=witness`, no OSD on
the witness, clean PGs, and healthy VMs:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph osd tree
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Securely erase or destroy the failed server's boot disk and never reconnect its old
installation.

## Emergency Stop Conditions

For either procedure, stop all removals if Proxmox or Ceph quorum changes unexpectedly,
a data site or another MON fails, a PG becomes `inactive`/`incomplete`/`stale`/`unknown`,
client I/O fails, or the replacement has clock skew, wrong versions/location, duplicate
identity, or unstable networking.
