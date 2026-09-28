# Expand the Proxmox Ceph Stretch Cluster

Use this guide to add one OSD host at OCC and one at BOCC. The target is three
Proxmox/OSD servers per data site while retaining exactly five MONs: two OCC, two
BOCC, and one tiebreaker.

> [!IMPORTANT]
> `occ3` and `bocc3` are OSD hosts, not MON hosts. Change one site at a time and wait
> for all PGs to return to `active+clean` between changes.

The data sites contain two node classes: `occ1`/`occ2` and `bocc1`/`bocc2` run both
OSDs and MONs; `occ3` and `bocc3` run OSDs only. All VM disks use shared Ceph storage.
Use the exact LACP, VLAN, and IP assignments in
[Production Network Configuration](ceph-network-configuration.md).

## 1. Pre-change Evidence and Gates

Run on a healthy monitor such as `occ1`:

```bash
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/ceph-expansion-$STAMP
install -d -m 0700 "$BACKUP"

pveversion -v | tee "$BACKUP/pveversion.txt"
ceph versions | tee "$BACKUP/versions.txt"
ceph -s | tee "$BACKUP/status-before.txt"
ceph health detail | tee "$BACKUP/health-before.txt"
ceph quorum_status -f json-pretty | tee "$BACKUP/quorum-before.json"
ceph mon dump -f json-pretty | tee "$BACKUP/monmap-before.json"
ceph osd tree | tee "$BACKUP/osd-tree-before.txt"
ceph osd crush tree | tee "$BACKUP/crush-tree-before.txt"
ceph osd crush rule dump | tee "$BACKUP/crush-rules-before.json"
ceph osd pool ls detail | tee "$BACKUP/pools-before.txt"
ceph df | tee "$BACKUP/df-before.txt"
ceph mon getmap -o "$BACKUP/monmap-before.bin"
ceph osd getcrushmap -o "$BACKUP/crushmap-before.bin"
cp -a /etc/pve/ceph.conf "$BACKUP/ceph.conf.before"
```

Proceed only when:

- All five intended MONs are in quorum.
- All existing OSDs are `up` and `in`; all PGs are `active+clean`.
- The stretch rule places two replicas in `occ` and two in `bocc`.
- No recovery, backfill, upgrade, or key migration is running.
- New servers run compatible Proxmox and Ceph package versions.

## 2. Validate Both New Servers

Before joining or creating OSDs, configure `bond0`/`vmbr0` with VLANs 111, 114, 115,
117, and 125, plus `bond1`/`vmbr1` with VLAN 118. The production assignments are:

| Host | Mgmt 111 | Corosync 114 | Migration 115 | Ceph public 117 | Ceph cluster 118 | Admin 125 |
| --- | --- | --- | --- | --- | --- | --- |
| `occ3` | `10.50.1.12/26` | `10.50.1.202/26` | `10.50.2.12/25` | `10.50.3.12/25` | `10.50.3.142/25` | `10.50.7.81/26` |
| `bocc3` | `10.50.1.22/26` | `10.50.1.205/26` | `10.50.2.15/25` | `10.50.3.15/25` | `10.50.3.145/25` | `10.50.7.74/26` |

> [!CAUTION]
> `bocc3` currently uses Ceph-public `10.50.3.15/25`, not the sequentially expected
> `.22`. Preserve it unless the formal network source of truth approves a correction.

Run on `occ3` and `bocc3`:

```bash
apt install chrony -y
systemctl enable --now chrony
chronyc tracking
chronyc sources -v
hostname -s
pveversion -v
getent hosts occ1 occ2 occ3 bocc1 bocc2 bocc3 quorum
readlink -f /etc/ceph/ceph.conf
test -r /etc/pve/ceph.conf
test -r /etc/pve/priv/ceph.client.admin.keyring
ceph -s
```

Verify both LACP bonds, VLAN-aware bridges, routes, MTU, and firewall policy. Required
Ceph ports include MON TCP 3300/6789 and OSD TCP 6800-7568.

```bash
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
bridge vlan show dev vmbr0
bridge vlan show dev vmbr1
ip -br address
ip route
ping -c 5 -I <local_vlan117_ip> <peer_vlan117_ip>
ping -c 5 -I <local_vlan118_ip> <peer_vlan118_ip>
ping -M do -s 1472 -c 5 -I <local_vlan118_ip> <peer_vlan118_ip>  # MTU 1500
# Use payload 8972 for MTU 9000.
```

Do not run `pveceph init`; `/etc/pve/ceph.conf` is cluster-wide.

## 3. Add `occ3`

Create and place its empty CRUSH host bucket before creating OSDs:

```bash
# Host: healthy Ceph monitor
ceph osd crush add-bucket occ3 host
ceph osd crush move occ3 datacenter=occ
ceph osd crush tree
```

The host must be below `datacenter occ`. On `occ3`, inspect disks carefully:

```bash
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Each following command destroys the selected disk:

```bash
pveceph osd create /dev/<verified_occ3_disk>
# Repeat for each verified blank OSD disk.
```

Monitor from `occ1`:

```bash
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
```

Do not start BOCC until all PGs are `active+clean`. Verify:

```bash
ceph osd tree
ceph osd df tree
ceph osd crush tree
```

## 4. Add `bocc3`

```bash
# Host: healthy Ceph monitor
ceph osd crush add-bucket bocc3 host
ceph osd crush move bocc3 datacenter=bocc
ceph osd crush tree
```

On `bocc3`:

```bash
pveceph install
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
pveceph osd create /dev/<verified_bocc3_disk>
# Repeat for each verified blank OSD disk.
```

Monitor until recovery completes:

```bash
watch -n 5 'ceph -s; ceph progress; ceph osd df tree'
ceph osd tree
ceph osd crush tree
```

Keep OSD count and usable capacity as symmetrical as practical. A four-copy stretch
pool is constrained by the site with less usable capacity.

## 5. Final Validation

```bash
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ceph df
```

Confirm `occ3` is below OCC, `bocc3` is below BOCC, all OSDs are `up`/`in`, all PGs
are `active+clean`, and every pool retains its intended stretch rule and four replicas.

Stop immediately if quorum is lost, any PG becomes `inactive`/`incomplete`, client I/O
fails, another host fails, or capacity reaches `nearfull`, `backfillfull`, or `full`.
