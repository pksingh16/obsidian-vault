# Replace a Failed OSD-Only Proxmox Node

This runbook applies only to `occ3` or `bocc3`: the server runs Ceph OSDs but no
Ceph MON. It may host QEMU VMs, and every VM disk is on shared Ceph storage.

Choose exactly one complete procedure:

- **Procedure A:** replacement keeps the same hostname and IP addresses.
- **Procedure B:** replacement uses a different hostname and IP addresses.

Production uses LACP `bond0`/VLAN-aware `vmbr0` and LACP
`bond1`/VLAN-aware `vmbr1`. The canonical details are in
[Production Network Configuration](ceph-network-configuration.md).

| Host | Mgmt 111 | Corosync 114 | Migration 115 | Ceph public 117 | Ceph cluster 118 | Admin 125 |
| --- | --- | --- | --- | --- | --- | --- |
| `occ3` | `10.50.1.12/26` | `10.50.1.202/26` | `10.50.2.12/25` | `10.50.3.12/25` | `10.50.3.142/25` | `10.50.7.81/26` |
| `bocc3` | `10.50.1.22/26` | `10.50.1.205/26` | `10.50.2.15/25` | `10.50.3.15/25` | `10.50.3.145/25` | `10.50.7.74/26` |

> [!CAUTION]
> Preserve `bocc3` Ceph-public `10.50.3.15/25` unless the formal network source of
> truth approves a correction; do not infer `.22` from the hostname sequence.

## Non-Destructive Rehearsal

For a dry run against a healthy node, run only the identity definition, health checks,
and evidence-capture sections:

- Procedure A: A1, A3, A4, and the inspection portion of A5.
- Procedure B: B1, B2 health commands, B3, and the inspection portion of B4.

The target may correctly appear `active` during a rehearsal. Do not fence it, move VM
configuration files, mark OSDs `out`, purge OSDs, remove CRUSH entries, call
`pvecm delnode`, delete `/etc/pve/nodes/<node>`, or run replacement-host commands.

> [!IMPORTANT]
> A dry run still requires the identity variables. Run A1 or B1 in the same shell
> before the capture block. A directory named `replace--<timestamp>` means
> `OLD_NODE` was empty and that evidence bundle is invalid.

The capture is successful only when its printed VM count agrees with the target node's
QEMU inventory. A zero count is valid only when that node genuinely owns no VMs.

## Procedure A: Same Hostname and IP Addresses

### A1. Define and verify the replacement identity

These variables identify the failed node, recovery node, site, and reused networks.
They exist only in the current shell, so redefine them after every SSH login.

```bash
OLD_NODE=occ3
NEW_NODE=occ3
RECOVERY_NODE=occ1
SITE=occ
PVE_JOIN_IP=10.50.1.10
MGMT_IP='<old_management_ip>'
COROSYNC_IP='<old_corosync_ip>'
MIGRATION_IP='<old_migration_ip>'
CEPH_PUBLIC_IP='<old_ceph_public_ip>'
CEPH_CLUSTER_IP='<old_ceph_cluster_ip>'
ADMIN_IP='<old_admin_ip>'

printf 'OLD=%s NEW=%s RECOVERY=%s SITE=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$RECOVERY_NODE" "$SITE"

test -n "$OLD_NODE" && test -n "$NEW_NODE" && \
  test -n "$RECOVERY_NODE" && test -n "$SITE" || {
  echo 'STOP: one or more required variables are empty'
  false
}
test "$OLD_NODE" = "$NEW_NODE" || {
  echo 'STOP: Procedure A requires the same old and new hostname'
  false
}
```

Replace the example values before continuing. `OLD_NODE` and `NEW_NODE` must match in
this procedure. Shell variables do not survive logout, a new SSH connection, or a new
terminal. Rerun A1 before copying commands from any later section.

### A2. Fence the failed server

Power off, disconnect, or fence the failed hardware. The following procedure reuses
its hostname and IP addresses, so the old server must be unable to boot or communicate.

> [!DANGER]
> Do not continue until fencing is independently confirmed. Duplicate Proxmox node
> names, Corosync identities, or IP addresses can disrupt cluster quorum.

### A3. Check that the surviving cluster can tolerate recovery

These commands verify Proxmox quorum, Ceph quorum, PG state, and failed-node OSDs.
They do not change cluster state.

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm nodes
ha-manager status
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph osd tree
```

Continue only if Proxmox and Ceph have quorum, client I/O works, no second server or
site has failed, and no PG is `inactive`, `incomplete`, `stale`, or `unknown`.
Degraded/undersized PGs caused solely by the failed OSDs are expected temporarily.

### A4. Capture VM allocation, policy, and Ceph state

This creates an evidence bundle before VM configurations or node membership change.
It records VM placement, HA/affinity rules, storage restrictions, mappings, jobs, and
Ceph topology. Copy the finished bundle off-cluster.

The bundle contains these configuration sources and generated reports:

| Source or report | Definition and recovery use |
| --- | --- |
| `/etc/pve/datacenter.cfg` | Cluster-wide Proxmox options, including migration, fencing, and scheduling behavior. |
| `/etc/pve/storage.cfg` | Shared storage definitions and any node restrictions; it references Ceph storage but does not contain VM disks. |
| `/etc/pve/corosync.conf` | Proxmox cluster membership, node IDs, links, and quorum communication configuration. Do not restore it blindly. |
| `/etc/pve/ha/` | HA groups, rules, and managed-resource policy. |
| `/etc/pve/nodes/$OLD_NODE/` | Failed node's Proxmox configuration subtree, including QEMU VM configuration files. |
| `/etc/pve/mapping/` | Optional cluster PCI and USB resource mappings used by VMs. |
| `/etc/pve/firewall/` | Cluster, host, and guest firewall configuration and aliases. |
| `vm-resources.json` | Cluster VM inventory and current node ownership from the Proxmox API. |
| `ha-*.json` and `ha-*.txt` | HA status, groups, and managed VM definitions. |
| `backup-jobs.json` | Scheduled Proxmox backup jobs and their node/storage selections. |
| `storage.json` | API view of configured Proxmox storage and node availability. |
| `config-files.txt` | Full paths of QEMU configuration files found under the failed node. |
| `vm-list.txt` | VMIDs extracted from `config-files.txt`; an empty file is valid only when the failed node had no VMs. |
| `qm-<VMID>.conf` | Expanded Proxmox configuration for one VM, including its disks, NICs, tags, and boot settings. |
| `qm-<VMID>.status` | VM runtime state at capture time. |
| `node-policy-references.txt` | References to the old hostname in HA, storage, jobs, and cluster policy. |
| `ceph.conf` | Ceph client and daemon configuration exposed through the Proxmox cluster filesystem. |
| `status.txt` and `health.txt` | Ceph health summaries captured before destructive changes. |
| `osd-tree.txt`, `osd-metadata.json`, `osd-dump.txt` | OSD identity, host placement, device metadata, and cluster-map state. |
| `crushmap.bin` | Binary copy of the CRUSH placement map for forensic recovery; do not import it during normal replacement. |

The preflight below intentionally stops if a required variable is empty, the command
is running on the wrong node, or the failed node is absent from `/etc/pve/nodes`.
Unlike the previous command, it does not hide a failed VM-directory lookup.

```bash
# Run on RECOVERY_NODE.
# Parentheses isolate this strict-mode capture from your interactive shell.
(
set -euo pipefail

: "${OLD_NODE:?Rerun A1: OLD_NODE is empty}"
: "${NEW_NODE:?Rerun A1: NEW_NODE is empty}"
: "${RECOVERY_NODE:?Rerun A1: RECOVERY_NODE is empty}"
test "$OLD_NODE" = "$NEW_NODE" || {
  echo 'STOP: Procedure A requires OLD_NODE and NEW_NODE to match'
  exit 1
}
test "$(hostname -s)" = "$RECOVERY_NODE" || {
  echo "STOP: run this on $RECOVERY_NODE, not $(hostname -s)"
  exit 1
}
test "$OLD_NODE" != "$RECOVERY_NODE" || {
  echo 'STOP: the failed node cannot be the recovery node'
  exit 1
}
test -d "/etc/pve/nodes/$OLD_NODE" || {
  echo "STOP: /etc/pve/nodes/$OLD_NODE does not exist"
  exit 1
}

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/replace-$OLD_NODE-$STAMP
install -d -m 0700 "$BACKUP"/{pve,ceph,vms}

pvecm status > "$BACKUP/pve/pvecm-status.txt"
pvecm nodes > "$BACKUP/pve/pvecm-nodes.txt"
pveversion -v > "$BACKUP/pve/pveversion.txt"
ha-manager status > "$BACKUP/pve/ha-status.txt"
ha-manager config > "$BACKUP/pve/ha-config.txt"
pvesh get /cluster/resources --type vm --output-format json-pretty \
  > "$BACKUP/pve/vm-resources.json"
pvesh get /cluster/ha/groups --output-format json-pretty \
  > "$BACKUP/pve/ha-groups.json" 2>&1 || true
pvesh get /cluster/ha/resources --output-format json-pretty \
  > "$BACKUP/pve/ha-resources.json" 2>&1 || true
pvesh get /cluster/backup --output-format json-pretty \
  > "$BACKUP/pve/backup-jobs.json" 2>&1 || true
pvesh get /cluster/firewall/aliases --output-format json-pretty \
  > "$BACKUP/pve/firewall-aliases.json" 2>&1 || true
pvesh get /cluster/mapping/pci --output-format json-pretty \
  > "$BACKUP/pve/pci-mappings.json" 2>&1 || true
pvesh get /cluster/mapping/usb --output-format json-pretty \
  > "$BACKUP/pve/usb-mappings.json" 2>&1 || true
pvesh get /storage --output-format json-pretty > "$BACKUP/pve/storage.json"

cp -a /etc/pve/datacenter.cfg /etc/pve/storage.cfg \
  /etc/pve/corosync.conf "$BACKUP/pve/"
cp -a /etc/pve/ha "$BACKUP/pve/ha-directory"
cp -a "/etc/pve/nodes/$OLD_NODE" "$BACKUP/pve/old-node-directory"
cp -a /etc/pve/mapping "$BACKUP/pve/mapping-directory" 2>/dev/null || true
cp -a /etc/pve/firewall "$BACKUP/pve/firewall-directory" 2>/dev/null || true

if test -d "/etc/pve/nodes/$OLD_NODE/qemu-server"; then
  find "/etc/pve/nodes/$OLD_NODE/qemu-server" -maxdepth 1 \
    -type f -name '[0-9]*.conf' -print | sort \
    > "$BACKUP/vms/config-files.txt"
else
  : > "$BACKUP/vms/config-files.txt"
fi
awk -F/ '/qemu-server\/[0-9]+\.conf$/ {gsub(/\.conf/,"",$NF); print $NF}' \
  "$BACKUP/vms/config-files.txt" > "$BACKUP/vms/vm-list.txt"
while read -r VMID; do
  qm config "$VMID" > "$BACKUP/vms/qm-$VMID.conf"
  qm status "$VMID" > "$BACKUP/vms/qm-$VMID.status"
done < "$BACKUP/vms/vm-list.txt"

grep -RnwE "$OLD_NODE|affinity|group|restricted|nodes[=:]" \
  /etc/pve/ha /etc/pve/datacenter.cfg /etc/pve/storage.cfg \
  /etc/pve/jobs.cfg 2>/dev/null \
  > "$BACKUP/pve/node-policy-references.txt" || true

ceph -s > "$BACKUP/ceph/status.txt"
ceph health detail > "$BACKUP/ceph/health.txt"
ceph osd tree > "$BACKUP/ceph/osd-tree.txt"
ceph osd metadata -f json-pretty > "$BACKUP/ceph/osd-metadata.json"
ceph osd dump > "$BACKUP/ceph/osd-dump.txt"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"

printf 'Evidence bundle: %s\n' "$BACKUP"
printf 'VM configuration files: '
wc -l < "$BACKUP/vms/config-files.txt"
printf 'VMIDs captured: '
wc -l < "$BACKUP/vms/vm-list.txt"
cat "$BACKUP/vms/vm-list.txt"
)
```

The bundle contains sensitive cluster configuration. Store it securely outside the
cluster before continuing. If the VM count is zero but `ha-manager status` or
`vm-resources.json` associates VMs with `OLD_NODE`, stop and investigate before A5.
Because A4 runs in a protective subshell, set `BACKUP` to the printed evidence-bundle
path before running A5, for example:

```bash
BACKUP=/root/replace-occ3-20260917-142500
```

### A5. Recover VMs onto surviving nodes

VM disks remain on shared Ceph. This step makes each VM configuration authoritative
on one surviving node before the failed node entry is deleted.

First inspect HA recovery and ensure no VMID is running or configured twice:

```bash
# Run on RECOVERY_NODE.
: "${OLD_NODE:?Rerun A1: OLD_NODE is empty}"
: "${BACKUP:?Set BACKUP to the complete evidence-bundle path from A4}"
test -r "$BACKUP/vms/vm-list.txt" || {
  echo 'STOP: VM inventory is missing'
  false
}
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

For HA-managed VMs, allow HA recovery to complete. For each non-HA VM still configured
only under the failed node, the next command moves its configuration to
`RECOVERY_NODE`; it does not move the Ceph-backed disks.

```bash
# Run once per verified non-HA VM.
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

Validate the application and QEMU guest agent after each start. Stop if any disk line
in `qm config` references node-local storage.

### A6. Remove each permanently lost OSD

The next commands identify and evacuate one old OSD. Marking it `out` triggers data
recovery onto surviving OSDs. Substitute only an OSD whose metadata names `OLD_NODE`.

```bash
# Run on RECOVERY_NODE, one OSD at a time.
: "${OLD_NODE:?Rerun A1: OLD_NODE is empty}"
OSD_ID=<old_osd_id>
: "${OSD_ID:?Set OSD_ID to one failed-node OSD number}"
command -v jq >/dev/null || {
  echo 'STOP: install jq before running the OSD ownership check'
  false
}
case "$OSD_ID" in
  *[!0-9]*|'') echo 'STOP: OSD_ID must contain digits only'; false ;;
esac
ceph osd find "$OSD_ID"
ceph osd metadata "$OSD_ID" -f json-pretty
ceph osd metadata "$OSD_ID" -f json | \
  jq -e --arg host "$OLD_NODE" '.hostname == $host' >/dev/null || {
  echo "STOP: osd.$OSD_ID does not belong to $OLD_NODE"
  false
}
ceph osd out "$OSD_ID"
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

Exit `watch` with `Ctrl+C` only after recovery settles. The following check asks Ceph
whether all required data has been recovered away from that OSD:

```bash
ceph osd safe-to-destroy "$OSD_ID"
```

> [!DANGER]
> Run the purge only when `safe-to-destroy` succeeds. Purging removes the OSD ID,
> authentication entry, and CRUSH entry from the cluster.

```bash
ceph osd safe-to-destroy "$OSD_ID"
ceph osd purge "$OSD_ID" --yes-i-really-mean-it
ceph osd tree
```

Repeat A6 for each failed OSD. Keep the empty `$OLD_NODE` CRUSH host bucket because
the replacement uses the same hostname.

### A7. Remove stale Proxmox membership and node files

The next command removes the fenced node from Corosync membership. It does not delete
shared Ceph VM disks.

```bash
# Run on RECOVERY_NODE.
: "${OLD_NODE:?Rerun A1: OLD_NODE is empty}"
: "${RECOVERY_NODE:?Rerun A1: RECOVERY_NODE is empty}"
test "$OLD_NODE" != "$RECOVERY_NODE" || {
  echo 'STOP: refusing to remove the recovery node'
  false
}
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

The stale node directory can block same-name rejoin. The next block refuses to run
unless both names match, displays remaining files, and then removes only the stale
Proxmox node directory. Confirm every VM configuration is recovered and the evidence
bundle is off-cluster first.

```bash
# Run on RECOVERY_NODE.
test -n "$OLD_NODE" && test "$OLD_NODE" = "$NEW_NODE" || {
  echo 'STOP: not a same-name replacement'
  false
}
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### A8. Build and join the replacement

Install the same Proxmox VE, kernel family, Ceph release, repository configuration,
and firmware baseline as a healthy peer. Configure the old hostname and every old
management, Corosync, migration, Ceph public, Ceph cluster, and admin IP before
joining.

Because IPs are reused with new NIC MAC addresses, update switch port security, LACP,
DHCP reservations, ARP inspection, monitoring, DNS/IPAM, and MAC-based ACLs. Clear
stale network-neighbor entries through the owning network platform. Verify the failed
server remains fenced.

These commands verify identity, networking, time, and package versions without joining:

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
apt-cache policy ceph-common ceph-osd
```

Compare all output with a healthy peer and the evidence bundle. Then join the existing
Proxmox cluster; this replaces the replacement's local `/etc/pve` with the shared
cluster filesystem.

```bash
# Run on the replacement.
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`. Do not restore old per-daemon Cephx keys or copy the failed
node's `/var/lib/ceph`; `pveceph osd create` generates new OSD identities and keys.

### A9. Create replacement OSDs

The next commands install Ceph packages and display disk serials. They do not modify
data disks.

```bash
# Run on the replacement.
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Confirm the retained same-name CRUSH host bucket is under the correct site:

```bash
# Run on RECOVERY_NODE.
ceph osd crush tree
```

Each following command destroys the selected replacement disk and creates a new OSD
with a new Cephx identity. Create one at a time when recovery load is significant.

```bash
# Run on the replacement.
pveceph osd create /dev/<verified_blank_disk>
```

After each OSD, monitor from `RECOVERY_NODE` until placement is correct and PGs are
`active+clean`:

```bash
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
ceph osd tree
ceph osd crush tree
```

### A10. Restore VM placement policy and finish

The same hostname normally makes node-based policy references valid again. Compare
live policy with the evidence bundle instead of overwriting cluster-wide files.

```bash
# Run on RECOVERY_NODE.
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Return VMs deliberately using supported online migration where appropriate. Verify
HA state, affinity, tags, pools, startup order, mappings, backup inclusion, VM disks,
QEMU guest agent, networking, and application health.

The following final checks must show the replacement in Proxmox quorum, replacement
OSDs `up`/`in` under the correct site, and all PGs `active+clean`:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ha-manager status
```

Securely erase or destroy the failed server's boot and Ceph disks. Never reconnect
its old installation to a network that can reach the cluster.

---

## Procedure B: Different Hostname and IP Addresses

### B1. Define and verify both identities

These variables identify the failed node, replacement, recovery node, site, and new
network addresses. Redefine them after every SSH login.

```bash
OLD_NODE=occ3
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

printf 'OLD=%s NEW=%s RECOVERY=%s SITE=%s\n' \
  "$OLD_NODE" "$NEW_NODE" "$RECOVERY_NODE" "$SITE"

test -n "$OLD_NODE" && test -n "$NEW_NODE" && \
  test -n "$RECOVERY_NODE" && test -n "$SITE" || {
  echo 'STOP: one or more required variables are empty'
  false
}
test "$OLD_NODE" != "$NEW_NODE" || {
  echo 'STOP: Procedure B requires different old and new hostnames'
  false
}
```

`OLD_NODE` and `NEW_NODE` must differ in this procedure. Shell variables do not
survive logout, a new SSH connection, or a new terminal. Rerun B1 before copying
commands from any later section.

### B2. Fence the failed server and verify cluster health

Power off or fence the failed hardware permanently. The following commands only
inspect surviving quorum and Ceph state:

```bash
# Run on RECOVERY_NODE.
pvecm status
pvecm nodes
ha-manager status
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph osd tree
```

Continue only with Proxmox/Ceph quorum, working client I/O, no second host/site
failure, and no `inactive`, `incomplete`, `stale`, or `unknown` PG.

### B3. Capture VM allocation, policy, and Ceph state

This evidence bundle preserves everything needed to translate old hostname/IP policy
to the new identity. Copy it off-cluster before continuing.

The bundle contains these configuration sources and generated reports:

| Source or report | Definition and recovery use |
| --- | --- |
| `/etc/pve/datacenter.cfg` | Cluster-wide Proxmox options, including migration, fencing, and scheduling behavior. |
| `/etc/pve/storage.cfg` | Shared storage definitions and node restrictions; it references Ceph storage but does not contain VM disks. |
| `/etc/pve/corosync.conf` | Proxmox membership, node IDs, links, and quorum communication configuration. Do not restore it blindly. |
| `/etc/pve/ha/` | HA groups, rules, and managed-resource policy. |
| `/etc/pve/nodes/$OLD_NODE/` | Failed node's Proxmox configuration subtree, including QEMU VM configuration files. |
| `/etc/pve/mapping/` | Optional cluster PCI and USB resource mappings used by VMs. |
| `/etc/pve/firewall/` | Cluster, host, and guest firewall configuration and aliases. |
| `vm-resources.json` | Cluster VM inventory and current node ownership from the Proxmox API. |
| `ha-*.json` and `ha-*.txt` | HA status, groups, and managed VM definitions. |
| `backup-jobs.json` | Scheduled Proxmox backup jobs and their node/storage selections. |
| `storage.json` | API view of configured Proxmox storage and node availability. |
| `config-files.txt` | Full paths of QEMU configuration files found under the failed node. |
| `vm-list.txt` | VMIDs extracted from `config-files.txt`; an empty file is valid only when the failed node had no VMs. |
| `qm-<VMID>.conf` | Expanded configuration for one VM, including disks, NICs, tags, and boot settings. |
| `qm-<VMID>.status` | VM runtime state at capture time. |
| `node-policy-references.txt` | References to the old hostname in HA, storage, jobs, and cluster policy. |
| `ceph.conf` | Ceph client and daemon configuration exposed through the Proxmox cluster filesystem. |
| `status.txt` and `health.txt` | Ceph health summaries captured before destructive changes. |
| `osd-tree.txt`, `osd-metadata.json`, `osd-dump.txt` | OSD identity, host placement, device metadata, and cluster-map state. |
| `crushmap.bin` | Binary CRUSH placement map for forensic recovery; do not import it during normal replacement. |

These files are evidence for comparison. Do not blindly restore cluster-wide files.

```bash
# Run on RECOVERY_NODE.
# Parentheses isolate this strict-mode capture from your interactive shell.
(
set -euo pipefail

: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
: "${NEW_NODE:?Rerun B1: NEW_NODE is empty}"
: "${RECOVERY_NODE:?Rerun B1: RECOVERY_NODE is empty}"
test "$OLD_NODE" != "$NEW_NODE" || {
  echo 'STOP: Procedure B requires different old and new hostnames'
  exit 1
}
test "$(hostname -s)" = "$RECOVERY_NODE" || {
  echo "STOP: run this on $RECOVERY_NODE, not $(hostname -s)"
  exit 1
}
test "$OLD_NODE" != "$RECOVERY_NODE" || {
  echo 'STOP: the failed node cannot be the recovery node'
  exit 1
}
test -d "/etc/pve/nodes/$OLD_NODE" || {
  echo "STOP: /etc/pve/nodes/$OLD_NODE does not exist"
  exit 1
}

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/replace-$OLD_NODE-with-$NEW_NODE-$STAMP
install -d -m 0700 "$BACKUP"/{pve,ceph,vms}

pvecm status > "$BACKUP/pve/pvecm-status.txt"
pvecm nodes > "$BACKUP/pve/pvecm-nodes.txt"
pveversion -v > "$BACKUP/pve/pveversion.txt"
ha-manager status > "$BACKUP/pve/ha-status.txt"
ha-manager config > "$BACKUP/pve/ha-config.txt"
pvesh get /cluster/resources --type vm --output-format json-pretty \
  > "$BACKUP/pve/vm-resources.json"
pvesh get /cluster/ha/groups --output-format json-pretty \
  > "$BACKUP/pve/ha-groups.json" 2>&1 || true
pvesh get /cluster/ha/resources --output-format json-pretty \
  > "$BACKUP/pve/ha-resources.json" 2>&1 || true
pvesh get /cluster/backup --output-format json-pretty \
  > "$BACKUP/pve/backup-jobs.json" 2>&1 || true
pvesh get /cluster/firewall/aliases --output-format json-pretty \
  > "$BACKUP/pve/firewall-aliases.json" 2>&1 || true
pvesh get /cluster/mapping/pci --output-format json-pretty \
  > "$BACKUP/pve/pci-mappings.json" 2>&1 || true
pvesh get /cluster/mapping/usb --output-format json-pretty \
  > "$BACKUP/pve/usb-mappings.json" 2>&1 || true
pvesh get /storage --output-format json-pretty > "$BACKUP/pve/storage.json"

cp -a /etc/pve/datacenter.cfg /etc/pve/storage.cfg \
  /etc/pve/corosync.conf "$BACKUP/pve/"
cp -a /etc/pve/ha "$BACKUP/pve/ha-directory"
cp -a "/etc/pve/nodes/$OLD_NODE" "$BACKUP/pve/old-node-directory"
cp -a /etc/pve/mapping "$BACKUP/pve/mapping-directory" 2>/dev/null || true
cp -a /etc/pve/firewall "$BACKUP/pve/firewall-directory" 2>/dev/null || true

if test -d "/etc/pve/nodes/$OLD_NODE/qemu-server"; then
  find "/etc/pve/nodes/$OLD_NODE/qemu-server" -maxdepth 1 \
    -type f -name '[0-9]*.conf' -print | sort \
    > "$BACKUP/vms/config-files.txt"
else
  : > "$BACKUP/vms/config-files.txt"
fi
awk -F/ '/qemu-server\/[0-9]+\.conf$/ {gsub(/\.conf/,"",$NF); print $NF}' \
  "$BACKUP/vms/config-files.txt" > "$BACKUP/vms/vm-list.txt"
while read -r VMID; do
  qm config "$VMID" > "$BACKUP/vms/qm-$VMID.conf"
  qm status "$VMID" > "$BACKUP/vms/qm-$VMID.status"
done < "$BACKUP/vms/vm-list.txt"

grep -RnwE "$OLD_NODE|affinity|group|restricted|nodes[=:]" \
  /etc/pve/ha /etc/pve/datacenter.cfg /etc/pve/storage.cfg \
  /etc/pve/jobs.cfg 2>/dev/null \
  > "$BACKUP/pve/node-policy-references.txt" || true

ceph -s > "$BACKUP/ceph/status.txt"
ceph health detail > "$BACKUP/ceph/health.txt"
ceph osd tree > "$BACKUP/ceph/osd-tree.txt"
ceph osd metadata -f json-pretty > "$BACKUP/ceph/osd-metadata.json"
ceph osd dump > "$BACKUP/ceph/osd-dump.txt"
ceph osd getcrushmap -o "$BACKUP/ceph/crushmap.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph/ceph.conf"
chmod -R go-rwx "$BACKUP"

printf 'Evidence bundle: %s\n' "$BACKUP"
printf 'VM configuration files: '
wc -l < "$BACKUP/vms/config-files.txt"
printf 'VMIDs captured: '
wc -l < "$BACKUP/vms/vm-list.txt"
cat "$BACKUP/vms/vm-list.txt"
)
```

If the VM count is zero but `ha-manager status` or `vm-resources.json` associates VMs
with `OLD_NODE`, stop and investigate before B4. Because B3 runs in a protective
subshell, set `BACKUP` to the printed evidence-bundle path before running B4, for
example:

```bash
BACKUP=/root/replace-occ3-with-occ4-20260917-142500
```

### B4. Recover VMs onto surviving nodes

VM disks remain on shared Ceph. Inspect HA recovery and ensure each VMID has only one
configuration before moving any non-HA VM configuration:

```bash
# Run on RECOVERY_NODE.
: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
: "${BACKUP:?Set BACKUP to the complete evidence-bundle path from B3}"
test -r "$BACKUP/vms/vm-list.txt" || {
  echo 'STOP: VM inventory is missing'
  false
}
ha-manager status
while read -r VMID; do
  echo "=== VM $VMID ==="
  ls -l /etc/pve/nodes/*/qemu-server/$VMID.conf 2>/dev/null || true
  qm status "$VMID" 2>/dev/null || true
done < "$BACKUP/vms/vm-list.txt"
```

For each verified non-HA VM still under the failed node, this moves only its
configuration to `RECOVERY_NODE`, then starts it against the existing Ceph disks:

```bash
VMID=<vmid>
mv "/etc/pve/nodes/$OLD_NODE/qemu-server/$VMID.conf" \
   "/etc/pve/nodes/$RECOVERY_NODE/qemu-server/$VMID.conf"
qm config "$VMID"
qm start "$VMID"
qm status "$VMID"
```

Validate application health and stop if any VM disk references node-local storage.

### B5. Remove each permanently lost OSD

Process one OSD whose metadata names `OLD_NODE`. Marking it out starts recovery:

```bash
# Run on RECOVERY_NODE.
: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
OSD_ID=<old_osd_id>
: "${OSD_ID:?Set OSD_ID to one failed-node OSD number}"
command -v jq >/dev/null || {
  echo 'STOP: install jq before running the OSD ownership check'
  false
}
case "$OSD_ID" in
  *[!0-9]*|'') echo 'STOP: OSD_ID must contain digits only'; false ;;
esac
ceph osd find "$OSD_ID"
ceph osd metadata "$OSD_ID" -f json-pretty
ceph osd metadata "$OSD_ID" -f json | \
  jq -e --arg host "$OLD_NODE" '.hostname == $host' >/dev/null || {
  echo "STOP: osd.$OSD_ID does not belong to $OLD_NODE"
  false
}
ceph osd out "$OSD_ID"
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

After recovery settles, ask Ceph whether the OSD can be destroyed:

```bash
ceph osd safe-to-destroy "$OSD_ID"
```

> [!DANGER]
> The purge permanently removes the old OSD's cluster records. Run it only after the
> preceding safety check succeeds.

```bash
ceph osd safe-to-destroy "$OSD_ID"
ceph osd purge "$OSD_ID" --yes-i-really-mean-it
```

Repeat for every failed OSD. The following removes the old CRUSH host bucket only
after it is empty because the replacement uses a different hostname:

```bash
: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
ceph osd crush tree
ceph osd crush remove "$OLD_NODE"
ceph osd crush tree
```

### B6. Remove failed Proxmox membership

This removes the fenced old node from Corosync. It does not remove shared VM disks:

```bash
# Run on RECOVERY_NODE.
: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
: "${RECOVERY_NODE:?Rerun B1: RECOVERY_NODE is empty}"
test "$OLD_NODE" != "$RECOVERY_NODE" || {
  echo 'STOP: refusing to remove the recovery node'
  false
}
pvecm status
pvecm delnode "$OLD_NODE"
pvecm status
pvecm nodes
```

After verifying every VM configuration is recovered and the evidence bundle is stored
off-cluster, inspect and remove only the stale old node directory:

```bash
: "${OLD_NODE:?Rerun B1: OLD_NODE is empty}"
: "${NEW_NODE:?Rerun B1: NEW_NODE is empty}"
test "$OLD_NODE" != "$NEW_NODE" || {
  echo 'STOP: Procedure B requires different old and new hostnames'
  false
}
find "/etc/pve/nodes/$OLD_NODE" -maxdepth 4 -type f -print
rm -rf -- "/etc/pve/nodes/$OLD_NODE"
test ! -e "/etc/pve/nodes/$OLD_NODE"
```

### B7. Build and join the replacement under its new identity

Install the same Proxmox VE, kernel family, Ceph release, repositories, and firmware
baseline as healthy nodes. Configure new DNS/IPAM, switch ports, bonds, bridges,
VLANs, routes, MTU, firewall, monitoring, BMC, and all six host L3 identities.

These commands verify the new identity before cluster join:

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
apt-cache policy ceph-common ceph-osd
```

After comparison with a healthy peer, join the existing Proxmox cluster:

```bash
pvecm add "$PVE_JOIN_IP"
pvecm status
systemctl --no-pager --full status corosync pve-cluster
readlink -f /etc/ceph/ceph.conf
ceph -s
```

Do not run `pveceph init`, restore old daemon keys, or copy old `/var/lib/ceph` data.
New OSD creation generates new Cephx identities and keys.

### B8. Create and place replacement OSDs

The following inventory is read-only; verify disk serials carefully:

```bash
# Run on the replacement.
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Each creation destroys the selected disk and creates a new OSD:

```bash
pveceph osd create /dev/<verified_blank_disk>
```

The next command moves the new CRUSH host under the correct site. It changes placement
for all OSDs beneath `NEW_NODE`:

```bash
# Run on RECOVERY_NODE.
ceph osd crush move "$NEW_NODE" datacenter="$SITE"
ceph osd crush tree
```

After each OSD, wait for recovery and `active+clean` PGs before adding the next:

```bash
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

### B9. Translate policy from old name/IP to new name/IP

Do not blindly restore cluster-wide files. Compare the evidence bundle, then update
references through the Proxmox UI or supported `ha-manager`/`pvesh` interfaces:

```bash
diff -ru "$BACKUP/pve/ha-directory" /etc/pve/ha || true
diff -u "$BACKUP/pve/datacenter.cfg" /etc/pve/datacenter.cfg || true
diff -u "$BACKUP/pve/storage.cfg" /etc/pve/storage.cfg || true
grep -Rnw "$OLD_NODE" /etc/pve/ha /etc/pve/*.cfg 2>/dev/null || true
```

Replace old references in HA groups/affinity, storage `nodes` restrictions, backup
jobs, PCI/USB mappings, firewall aliases, SDN, DNS/IPAM, monitoring, automation, and
external allowlists. Return VMs deliberately and validate HA state, disks, networking,
QEMU guest agent, application health, and backup inclusion after each migration.

### B10. Final validation

The following must show `NEW_NODE` in Proxmox quorum, no `OLD_NODE`, replacement OSDs
under the correct site, and all PGs `active+clean`:

```bash
pvecm status
pvecm nodes
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ha-manager status
pvesh get /cluster/resources --type vm --output-format json-pretty
```

Securely erase or destroy the failed server's boot and Ceph disks. Never reconnect
its old installation to a network that can reach the cluster.

## Emergency Stop Conditions

For either procedure, stop all removal if Proxmox or Ceph quorum changes unexpectedly,
another host/site fails, a PG becomes `inactive`/`incomplete`/`stale`/`unknown`, client
I/O fails, capacity approaches `backfillfull`, or the replacement has clock skew,
version mismatch, wrong CRUSH placement, duplicate identity, or unstable networking.
