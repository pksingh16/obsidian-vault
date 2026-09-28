# Proxmox and Ceph Stretch Cluster Deployment from Scratch

This runbook builds a new seven-node Proxmox VE cluster and a Ceph stretch cluster
across two data sites with one witness:

For other operations, use the [Ceph runbook index](ceph-setup.md). The canonical
production bond, VLAN, and IP assignments are in
[Production Network Configuration](ceph-network-configuration.md).

| Site | Proxmox nodes | Ceph services |
| --- | --- | --- |
| OCC | `occ1`, `occ2`, `occ3` | OSDs on all three; MONs on `occ1` and `occ2` |
| BOCC | `bocc1`, `bocc2`, `bocc3` | OSDs on all three; MONs on `bocc1` and `bocc2` |
| Witness | `quorum` | One MON, no OSD; may host VMs on shared Ceph |

The final Ceph monitor layout is five monitors, not seven: two at OCC, two at BOCC,
and one tiebreaker at the witness site. Managers should run on data-site monitor nodes,
not on the witness. The witness may run QEMU VMs, but every VM disk must reside on
shared Ceph storage; there are no Proxmox containers or node-local VM disks.

> [!CAUTION]
> This procedure is for an empty, new environment. Commands that create OSDs destroy
> all data on the selected disks. Verify every hostname, IP address, network, and disk
> serial before running a command.

## 1. Architecture Gate

Ceph stretch mode and Proxmox quorum are separate systems:

- Ceph uses `mon.quorum` to choose between OCC and BOCC during a site split.
- Proxmox uses Corosync votes from all seven Proxmox nodes.
- The Ceph witness is not a substitute for a Proxmox Corosync QDevice.
- Proxmox discourages adding a QDevice to an odd-sized seven-node cluster.

Proxmox requires reliable LAN-like Corosync connectivity with latency below 5 ms
between **all** cluster nodes. Latency above approximately 10 ms is not guaranteed to
work, especially with more than three nodes. Do not build one stretched Proxmox
cluster if OCC, BOCC, and the witness cannot meet this requirement consistently under
load and during link degradation.

Use independent physical networks where possible:

| VLAN | Network | Participants | Purpose | Production path |
| --- | --- | --- | --- | --- |
| 111 | Management | All nodes | GUI, API, SSH, cluster join | `bond0` / `vmbr0` |
| 114 | Corosync | All nodes | Proxmox quorum | `bond0` / `vmbr0` under 5 ms |
| 115 | Migration | All nodes | VM live migration | `bond0` / `vmbr0` |
| 117 | Ceph public | All nodes | MON, client, OSD public traffic | `bond0` / `vmbr0` |
| 118 | Ceph cluster | Six OSD nodes | Replication and recovery | `bond1` / `vmbr1` |
| 125 | Administration | All nodes | Configuration and default route | `bond0` / `vmbr0` |

Production has one logical Corosync network, VLAN 114. Its physical resilience comes
from LACP across `nic0`/`nic2` and the redundant Server Farm switches; VLAN 115 is
migration, not a second Corosync ring. `quorum` needs Corosync and Ceph public
connectivity but has no VLAN 118 cluster-network interface because it has no OSDs.

## 2. Address and Hardware Worksheet

Complete this table before installation. Use static IP addresses and final hostnames;
changing them after creating the Proxmox cluster is not supported as a normal action.

| Node | Management 111 | Corosync 114 | Migration 115 | Ceph public 117 | Ceph cluster 118 | Admin 125 |
| --- | --- | --- | --- | --- | --- | --- |
| `occ1` | `10.50.1.10/26` | `10.50.1.200/26` | `10.50.2.10/25` | `10.50.3.10/25` | `10.50.3.140/25` | `10.50.7.69/26` |
| `occ2` | `10.50.1.11/26` | `10.50.1.201/26` | `10.50.2.11/25` | `10.50.3.11/25` | `10.50.3.141/25` | `10.50.7.70/26` |
| `occ3` | `10.50.1.12/26` | `10.50.1.202/26` | `10.50.2.12/25` | `10.50.3.12/25` | `10.50.3.142/25` | `10.50.7.81/26` |
| `bocc1` | `10.50.1.20/26` | `10.50.1.203/26` | `10.50.2.13/25` | `10.50.3.20/25` | `10.50.3.150/25` | `10.50.7.72/26` |
| `bocc2` | `10.50.1.21/26` | `10.50.1.204/26` | `10.50.2.14/25` | `10.50.3.21/25` | `10.50.3.151/25` | `10.50.7.73/26` |
| `bocc3` | `10.50.1.22/26` | `10.50.1.205/26` | `10.50.2.15/25` | `10.50.3.15/25` | `10.50.3.145/25` | `10.50.7.74/26` |
| `quorum` | `10.50.1.31/26` | `10.50.1.207/26` | `10.50.2.31/25` | `10.50.3.31/25` | N/A | `10.50.7.118/26` |

> [!CAUTION]
> Preserve the observed `bocc3` Ceph-public address `10.50.3.15/25`; do not infer
> `10.50.3.22/25` from the sequence. Verify the observed address against the formal
> network source of truth before deployment.

Record these cluster-wide values:

```text
Proxmox cluster name: <cluster_name>
Management network (VLAN 111): 10.50.1.0/26
Corosync network (VLAN 114): 10.50.1.192/26
Migration network (VLAN 115): 10.50.2.0/25
Ceph public network (VLAN 117): 10.50.3.0/25
Ceph cluster network (VLAN 118): 10.50.3.128/25
Administration network (VLAN 125): 10.50.7.64/26
Default gateway: 10.50.7.126
Supported Ceph release: <release>
Ceph repository: <enterprise|no-subscription|manual>
```

Use raw disks or HBAs for OSDs, not hardware RAID. Keep OSD count, media type, and
usable capacity symmetrical between OCC and BOCC. Upstream recommends SSD OSDs for
stretch mode because recovery from a site outage can be lengthy on HDDs.

## 3. Install and Prepare Proxmox VE

Install the same supported Proxmox VE release on all seven servers. During installation:

1. Set each final hostname exactly as listed in the worksheet.
2. Configure static management and Corosync addresses.
3. Configure `bond0` (`nic0` + `nic2`) as LACP beneath VLAN-aware `vmbr0`.
4. On OCC/BOCC, configure `bond1` (`nic1` + `nic3`) as LACP beneath VLAN-aware
    `vmbr1`; do not configure VLAN 118 on `quorum`.
5. Configure host L3 subinterfaces for VLANs 111, 114, 115, 117, 125, plus VLAN 118
    on OCC/BOCC only, using the canonical address table.
6. Keep the operating-system disk separate from Ceph OSD disks.
7. Configure redundant DNS and NTP sources reachable from both sites.
8. Do not create VMs or cluster-local configuration on nodes that will join later.

After installation, configure the appropriate supported Proxmox repository and update
every node. Do not mix enterprise, test, or no-subscription repositories unintentionally:

```bash
apt update
apt full-upgrade -y
pveversion -v
reboot
```

After reboot, run on every node:

```bash
apt install chrony -y
systemctl enable --now chrony
chronyc tracking
chronyc sources -v
hostname -s
hostname -f
```

Ensure every node resolves all seven final hostnames consistently through DNS or
`/etc/hosts`:

```bash
getent hosts occ1 occ2 occ3 bocc1 bocc2 bocc3 quorum
```

Verify that `/etc/hostname`, `/etc/hosts`, DNS, and the management certificate name
agree before creating the cluster.

## 4. Validate Networks Before Clustering

First verify LACP membership, VLAN-aware bridges, host addresses, and routes. On every
node:

```bash
cat /proc/net/bonding/bond0
bridge vlan show dev vmbr0
ip -br address
ip route
```

On OCC and BOCC nodes also verify `bond1`, `vmbr1`, and VLAN 118:

```bash
cat /proc/net/bonding/bond1
bridge vlan show dev vmbr1
ip address show dev vmbr1.118
```

On `quorum`, confirm VLAN 118 is absent. Then test every peer over VLAN 114 and
capture latency, jitter, and packet loss during representative load:

```bash
ping -c 100 -I <local_vlan114_ip> <peer_vlan114_ip>
ping -c 5 -I <local_vlan115_ip> <peer_vlan115_ip>
ping -c 5 -I <local_vlan117_ip> <peer_vlan117_ip>
# OCC and BOCC only:
ping -c 5 -I <local_vlan118_ip> <peer_vlan118_ip>
```

There must be no packet loss and latency must remain below 5 ms. Test MTU end to end:

```bash
ping -M do -s 1472 -c 5 <peer_ip>  # IPv4, MTU 1500
ping -M do -s 8972 -c 5 <peer_ip>  # IPv4, MTU 9000
```

Use only the line matching the configured MTU. Also verify:

- Corosync UDP 5405-5412 is permitted between every Proxmox node.
- SSH TCP 22 and Proxmox management TCP 8006 are reachable as required.
- Ceph MON TCP 3300 and 6789 is permitted on the Ceph public network.
- Ceph OSD TCP 6800-7568 is permitted between Ceph nodes.
- The Ceph public network does not congest Corosync on `bond0`/`vmbr0`.
- VLAN 114 remains available after either `bond0` member or Server Farm switch fails.
- VLAN 118 remains available after either `bond1` member or Storage switch fails.

## 5. Create the Proxmox Cluster

Create the cluster on `occ1` using its VLAN 114 Corosync address:

```bash
pvecm create <cluster_name> --link0 10.50.1.200

pvecm status
systemctl status corosync --no-pager
journalctl -b -u corosync --no-pager -n 100
```

Join the other six nodes one at a time. Run this on the joining node, using `occ1`'s
VLAN 111 management address as the seed and the joining node's VLAN 114 address as
its Corosync `link0`:

```bash
pvecm add 10.50.1.10 --link0 <joining_node_vlan114_ip>
```

Use this order and validate after each join:

```text
occ2, occ3, bocc1, bocc2, bocc3, quorum
```

From `occ1` after every join:

```bash
pvecm status
pvecm nodes
```

At completion, all seven nodes must be listed and `Quorate` must be `Yes`. Verify the
VLAN 114 Corosync link from each node:

```bash
journalctl -b -u corosync --no-pager | grep -E 'link:|host:'
```

Do not configure HA until the complete Proxmox and Ceph failure tests have passed.

## 6. Install Ceph Packages

Select one Ceph release supported by the installed Proxmox VE version. Install the
same release and repository selection on all seven nodes. Example syntax:

```bash
pveceph install --version <supported_ceph_release> --repository <repository>
ceph --version
```

Run `pveversion -v` on every node and resolve version differences before continuing.
Do not initialize seven separate Ceph clusters.

## 7. Initialize Ceph Once

Run only on `occ1`. `--network` is the Ceph public network; `--cluster-network` is
the OSD replication network:

```bash
pveceph init \
    --network 10.50.3.0/25 \
    --cluster-network 10.50.3.128/25
```

Verify the configuration is distributed by `pmxcfs`:

```bash
cat /etc/pve/ceph.conf
readlink -f /etc/ceph/ceph.conf
```

On each remaining node:

```bash
test -r /etc/pve/ceph.conf
readlink -f /etc/ceph/ceph.conf
```

## 8. Create the Five Ceph Monitors

Create monitors before enabling stretch mode. This allows their locations to be set
normally after all monitor IDs exist.

Run each command on the named node, using that node's Ceph public IP:

```bash
# On occ1
pveceph mon create --mon-address 10.50.3.10

# On occ2
pveceph mon create --mon-address 10.50.3.11

# On bocc1
pveceph mon create --mon-address 10.50.3.20

# On bocc2
pveceph mon create --mon-address 10.50.3.21

# On quorum
pveceph mon create --mon-address 10.50.3.31
```

Use `--mon-address`, not `--mon-addr`. Check quorum after each monitor is created:

```bash
ceph -s
ceph mon stat
ceph quorum_status -f json-pretty
```

Do not create monitors on `occ3` or `bocc3`.

## 9. Create Ceph Managers

Creating the first monitor normally creates the first manager automatically. Verify it:

```bash
ceph mgr stat
```

Create at least two additional managers on data-site monitor nodes, for example on
`bocc1` and `occ2`:

```bash
# Run on bocc1
pveceph mgr create

# Run on occ2
pveceph mgr create
```

Verify one manager is active and the others are standby:

```bash
ceph mgr stat
```

Do not place a manager on `quorum` unless there is a separately justified need.

## 10. Build the OSD CRUSH Site Hierarchy

Run from `occ1` before creating any OSD:

```bash
ceph osd crush add-bucket occ datacenter
ceph osd crush add-bucket bocc datacenter
ceph osd crush move occ root=default
ceph osd crush move bocc root=default

ceph osd crush add-bucket occ1 host
ceph osd crush add-bucket occ2 host
ceph osd crush add-bucket occ3 host
ceph osd crush move occ1 datacenter=occ
ceph osd crush move occ2 datacenter=occ
ceph osd crush move occ3 datacenter=occ

ceph osd crush add-bucket bocc1 host
ceph osd crush add-bucket bocc2 host
ceph osd crush add-bucket bocc3 host
ceph osd crush move bocc1 datacenter=bocc
ceph osd crush move bocc2 datacenter=bocc
ceph osd crush move bocc3 datacenter=bocc

ceph osd crush tree
```

The `default` root must contain exactly the `occ` and `bocc` datacenter buckets for
this rule. Do not add a `witness` datacenter to the OSD CRUSH hierarchy; the witness
has no OSDs and its monitor location is maintained separately.

## 11. Create OSDs on the Six Data Nodes

On each OCC and BOCC data node, identify every disk by model and serial:

```bash
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Create one BlueStore OSD per verified raw disk. The selected device is erased:

```bash
pveceph osd create /dev/<verified_osd_disk>
```

Add one host at a time in this alternating order to maintain site balance:

```text
occ1, bocc1, occ2, bocc2, occ3, bocc3
```

After each host, verify that its OSDs appear under the correct CRUSH datacenter:

```bash
ceph -s
ceph osd tree
ceph osd df tree
ceph osd crush tree
```

Stop if an OSD appears below the wrong host or site. Move the host bucket to the
correct datacenter before creating more OSDs.

## 12. Set Monitor Locations

After all five monitors exist, run from `occ1`:

```bash
ceph mon set_location occ1 datacenter=occ
ceph mon set_location occ2 datacenter=occ
ceph mon set_location bocc1 datacenter=bocc
ceph mon set_location bocc2 datacenter=bocc
ceph mon set_location quorum datacenter=witness
ceph mon dump -f json-pretty
```

Do not set monitor locations for `occ3` or `bocc3`; they do not run monitors. The
logical `datacenter=witness` monitor location must differ from `occ` and `bocc` and
must not be an OSD datacenter bucket.

## 13. Create the Stretch CRUSH Rule

Back up the current CRUSH map and decompile it:

```bash
mkdir -p /root/ceph-initial-backup
chmod 700 /root/ceph-initial-backup
ceph osd getcrushmap -o /root/ceph-initial-backup/crushmap-before-stretch.bin
crushtool -d /root/ceph-initial-backup/crushmap-before-stretch.bin \
    -o /root/ceph-initial-backup/crushmap-before-stretch.txt
```

Copy the text map to a working file:

```bash
cp /root/ceph-initial-backup/crushmap-before-stretch.txt \
    /root/ceph-initial-backup/crushmap-with-stretch.txt
nano /root/ceph-initial-backup/crushmap-with-stretch.txt
```

Add the following rule with an unused numeric ID. Check existing rule IDs in the file
and replace `<unused_rule_id>`:

```text
rule stretch_rule {
    id <unused_rule_id>
    type replicated
    step take default
    step choose firstn 0 type datacenter
    step chooseleaf firstn 2 type host
    step emit
}
```

This rule selects two data sites and two hosts in each site. It must use `take default`
and must not specify an OSD device class. A class-based shadow tree can cause every PG
to become inactive during a site outage.

Compile the working map, inspect it, and inject it:

```bash
crushtool -c /root/ceph-initial-backup/crushmap-with-stretch.txt \
    -o /root/ceph-initial-backup/crushmap-with-stretch.bin
crushtool -d /root/ceph-initial-backup/crushmap-with-stretch.bin \
    -o /root/ceph-initial-backup/crushmap-compiled-check.txt
grep -A8 'rule stretch_rule' /root/ceph-initial-backup/crushmap-compiled-check.txt
ceph osd setcrushmap -i /root/ceph-initial-backup/crushmap-with-stretch.bin
ceph osd crush rule dump stretch_rule
```

## 14. Pre-stretch Validation

Run these checks before enabling stretch mode:

```bash
ceph -s
ceph health detail
ceph mon stat
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph mgr stat
ceph osd tree
ceph osd crush tree
ceph osd crush rule dump stretch_rule
ceph osd pool ls detail
```

Confirm:

- All five monitors are in quorum and have the intended locations.
- All OSDs are `up` and `in`, split evenly between OCC and BOCC.
- Every PG is `active+clean`.
- There are no erasure-coded pools; stretch mode does not support them.
- Every existing replicated pool has the default pre-stretch `size=3` and `min_size=2`.
- The stretch rule has no device class and chooses two hosts per datacenter.

## 15. Enable Ceph Stretch Mode

Run from `occ1`, explicitly naming `mon.quorum` as the tiebreaker:

```bash
ceph mon enable_stretch_mode quorum stretch_rule datacenter
```

Current Ceph releases automatically select the `connectivity` monitor election
strategy when stretch mode is enabled. Verify rather than setting it blindly:

```bash
ceph mon dump -f json-pretty
ceph -s
ceph health detail
ceph osd pool ls detail
```

In healthy stretch mode, replicated pools should use four copies, with two copies in
OCC and two in BOCC. Normal `min_size` should be two. The witness stores no data and
OSDs do not connect to the witness monitor.

## 16. Create Proxmox Ceph Storage

Create a replicated RBD pool using the stretch rule. Choose the initial PG count based
on expected capacity and OSD count; enable the autoscaler unless there is a documented
reason not to:

```bash
pveceph pool create <pool_name> \
    --size 4 \
    --min_size 2 \
    --crush_rule stretch_rule \
    --pg_autoscale_mode on \
    --add_storages 1
```

Verify the pool and Proxmox storage:

```bash
ceph osd pool get <pool_name> all
pvesm status
ceph -s
```

Do not create erasure-coded pools in stretch mode.

If CephFS is required, create at least two MDS daemons on different data-site nodes
before creating the filesystem. Do not place MDS on the witness:

```bash
# Run on one OCC data node.
pveceph mds create

# Run on one BOCC data node.
pveceph mds create
```

Confirm the CephFS metadata and data pools use `stretch_rule`, `size=4`, and
`min_size=2` after creation.

## 17. Configure Proxmox Migration and HA

Configure the dedicated migration network in Datacenter options or
`/etc/pve/datacenter.cfg`:

```text
migration: secure,network=10.50.2.0/25
```

Before enabling HA:

- Verify the watchdog configuration on every compute node.
- Verify VLAN 114 Corosync remains healthy through each `bond0` member/switch path.
- Confirm VM CPU compatibility for live migration.
- Create HA groups or rules that reflect OCC and BOCC placement policy.
- Ensure the surviving site has enough CPU, memory, and Ceph capacity for failover.
- Document whether a site outage should restart all VMs or only critical services.

Ceph data availability does not guarantee enough compute capacity to restart every
VM at one site.

## 18. Final Acceptance Checks

Save the final configuration and cluster maps:

```bash
ceph -s | tee /root/ceph-initial-backup/status-final.txt
ceph health detail | tee /root/ceph-initial-backup/health-final.txt
ceph quorum_status -f json-pretty \
    | tee /root/ceph-initial-backup/quorum-final.json
ceph mon dump -f json-pretty \
    | tee /root/ceph-initial-backup/mon-dump-final.json
ceph osd tree | tee /root/ceph-initial-backup/osd-tree-final.txt
ceph osd crush tree | tee /root/ceph-initial-backup/crush-tree-final.txt
ceph osd pool ls detail | tee /root/ceph-initial-backup/pools-final.txt
ceph osd getcrushmap -o /root/ceph-initial-backup/crushmap-final.bin
ceph mon getmap -o /root/ceph-initial-backup/monmap-final.bin
cp -a /etc/pve/ceph.conf /root/ceph-initial-backup/
cp -a /etc/pve/corosync.conf /root/ceph-initial-backup/
cp -a /etc/pve/priv/ceph.mon.keyring /root/ceph-initial-backup/
chmod -R go-rwx /root/ceph-initial-backup
```

The deployment is complete only when:

- All seven Proxmox nodes are online and Corosync is quorate.
- Corosync latency remains below 5 ms with no loss during load.
- VLAN 114 Corosync is operational through the redundant LACP physical paths.
- Exactly five Ceph monitors exist and all are in quorum.
- `occ1`/`occ2` monitor locations are `datacenter=occ`.
- `bocc1`/`bocc2` monitor locations are `datacenter=bocc`.
- `quorum` is the tiebreaker at `datacenter=witness`.
- All OSDs are beneath the correct OCC or BOCC CRUSH hosts.
- Every PG is `active+clean` and every OSD is `up` and `in`.
- Replicated pools use `stretch_rule`, `size=4`, and `min_size=2`.
- Proxmox can create, start, snapshot, migrate, and delete a test VM on Ceph storage.

Perform controlled host, monitor, network-link, and site-failure tests only under an
approved test plan with console access and a rollback procedure. Do not start by
disconnecting an entire production site.

## Important Operating Rules

- Keep two MONs at each data site and one MON at the witness site.
- Keep OSD capacity balanced between OCC and BOCC.
- Never place OSDs at the witness site.
- Never add the witness as an OSD CRUSH datacenter.
- Never use an OSD device class in the stretch rule.
- Never create erasure-coded pools while stretch mode is enabled.
- Change or restart one Ceph host at a time and wait for `active+clean`.
- Maintain at least three monitor votes during maintenance.
- Do not use `pvecm expected 1` as a routine recovery technique.
- Back up `/etc/pve`, the monmap, CRUSH map, and protected keyrings after changes.

## References

- [Proxmox VE cluster manager](https://pve.proxmox.com/pve-docs/chapter-pvecm.html)
- [Proxmox VE Ceph administration](https://pve.proxmox.com/pve-docs/chapter-pveceph.html)
- [Ceph stretch mode](https://docs.ceph.com/en/squid/rados/operations/stretch-mode/)
- [Ceph monitor addition and removal](https://docs.ceph.com/en/squid/rados/operations/add-or-rm-mons/)