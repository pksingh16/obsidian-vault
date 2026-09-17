# Proxmox and Ceph Stretch Cluster Deployment from Scratch

This runbook builds a new seven-node Proxmox VE cluster and a Ceph stretch cluster
across two data sites with one witness:

For expanding an existing cluster and replacing its witness, use
[[ceph-setup|Proxmox Ceph Stretch Cluster Expansion and Witness Replacement]].

| Site | Proxmox nodes | Ceph services |
| --- | --- | --- |
| OCC | `occ1`, `occ2`, `occ3` | OSDs on all three; MONs on `occ1` and `occ2` |
| BOCC | `bocc1`, `bocc2`, `bocc3` | OSDs on all three; MONs on `bocc1` and `bocc2` |
| Witness | `witness` | One MON only; no OSD |

The final Ceph monitor layout is five monitors, not seven: two at OCC, two at BOCC,
and one tiebreaker at the witness site. Managers should run on data-site monitor nodes,
not on the witness.

> [!CAUTION]
> This procedure is for an empty, new environment. Commands that create OSDs destroy
> all data on the selected disks. Verify every hostname, IP address, network, and disk
> serial before running a command.

## 1. Architecture Gate

Ceph stretch mode and Proxmox quorum are separate systems:

- Ceph uses `mon.witness` to choose between OCC and BOCC during a site split.
- Proxmox uses Corosync votes from all seven Proxmox nodes.
- The Ceph witness is not a substitute for a Proxmox Corosync QDevice.
- Proxmox discourages adding a QDevice to an odd-sized seven-node cluster.

Proxmox requires reliable LAN-like Corosync connectivity with latency below 5 ms
between **all** cluster nodes. Latency above approximately 10 ms is not guaranteed to
work, especially with more than three nodes. Do not build one stretched Proxmox
cluster if OCC, BOCC, and the witness cannot meet this requirement consistently under
load and during link degradation.

Use independent physical networks where possible:

| Network | Participants | Purpose | Guidance |
| --- | --- | --- | --- |
| Management | All nodes | GUI, API, SSH | Routed as required |
| Corosync link 0 | All nodes | Primary Proxmox quorum | Dedicated, under 5 ms |
| Corosync link 1 | All nodes | Redundant Proxmox quorum | Different physical path |
| Ceph public | All seven nodes | MON, client, OSD public traffic | 10 Gb/s or faster |
| Ceph cluster | Six OSD nodes | Replication and recovery | 25 Gb/s or faster |
| Migration | Six compute nodes | VM live migration | Dedicated high bandwidth |

The witness needs Corosync and Ceph public connectivity but does not need a Ceph
cluster-network interface because it has no OSDs.

## 2. Address and Hardware Worksheet

Complete this table before installation. Use static IP addresses and final hostnames;
changing them after creating the Proxmox cluster is not supported as a normal action.

| Node | Management | Corosync 0 | Corosync 1 | Ceph public | Ceph cluster | OSD disks |
| --- | --- | --- | --- | --- | --- | --- |
| `occ1` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `occ2` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `occ3` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `bocc1` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `bocc2` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `bocc3` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | `<devices>` |
| `witness` | `<ip>` | `<ip>` | `<ip>` | `<ip>` | N/A | None |

Record these cluster-wide values:

```text
Proxmox cluster name: <cluster_name>
Corosync link 0 network: <cidr>
Corosync link 1 network: <cidr>
Ceph public network: <cidr>
Ceph cluster network: <cidr>
Migration network: <cidr>
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
3. Keep the operating-system disk separate from Ceph OSD disks.
4. Configure redundant DNS and NTP sources reachable from both sites.
5. Do not create guests or cluster-local configuration on nodes that will join later.

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
getent hosts occ1 occ2 occ3 bocc1 bocc2 bocc3 witness
```

Verify that `/etc/hostname`, `/etc/hosts`, DNS, and the management certificate name
agree before creating the cluster.

## 4. Validate Networks Before Clustering

From every node, test every peer over both Corosync links. Capture latency, jitter, and
packet loss during a representative load test, not only when links are idle:

```bash
ping -c 100 <peer_corosync0_ip>
ping -c 100 <peer_corosync1_ip>
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
- The Ceph public and cluster networks do not share a congested Corosync link.
- Corosync links use different physical failure paths, not merely different VLANs on
  one cable or one switch.

## 5. Create the Proxmox Cluster

Create the cluster on `occ1`. Replace the placeholders with `occ1`'s local Corosync
addresses:

```bash
pvecm create <cluster_name> \
    --link0 <occ1_corosync0_ip>,priority=20 \
    --link1 <occ1_corosync1_ip>,priority=10

pvecm status
systemctl status corosync --no-pager
journalctl -b -u corosync --no-pager -n 100
```

The higher-priority link is preferred. Each link must use the same link number and
priority scheme on every node.

Join the other six nodes one at a time. Run this on the node being joined, using an
existing cluster node's Corosync link 0 address as `<cluster_ip>` and that joining
node's own local addresses for `--link0` and `--link1`:

```bash
pvecm add <cluster_ip> \
    --link0 <joining_node_corosync0_ip>,priority=20 \
    --link1 <joining_node_corosync1_ip>,priority=10
```

Use this order and validate after each join:

```text
occ2, occ3, bocc1, bocc2, bocc3, witness
```

From `occ1` after every join:

```bash
pvecm status
pvecm nodes
```

At completion, all seven nodes must be listed and `Quorate` must be `Yes`. Also verify
both Corosync links from each node:

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
    --network <ceph_public_cidr> \
    --cluster-network <ceph_cluster_cidr>
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
pveceph mon create --mon-address <occ1_ceph_public_ip>

# On occ2
pveceph mon create --mon-address <occ2_ceph_public_ip>

# On bocc1
pveceph mon create --mon-address <bocc1_ceph_public_ip>

# On bocc2
pveceph mon create --mon-address <bocc2_ceph_public_ip>

# On witness
pveceph mon create --mon-address <witness_ceph_public_ip>
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

Do not place a manager on `witness` unless there is a separately justified need.

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
ceph mon set_location witness datacenter=witness
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

Run from `occ1`, explicitly naming `mon.witness` as the tiebreaker:

```bash
ceph mon enable_stretch_mode witness stretch_rule datacenter
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
migration: secure,network=<migration_cidr>
```

Before enabling HA:

- Verify the watchdog configuration on every compute node.
- Verify both Corosync links and their independent failure paths.
- Confirm guest CPU compatibility for live migration.
- Create HA groups or rules that reflect OCC and BOCC placement policy.
- Ensure the surviving site has enough CPU, memory, and Ceph capacity for failover.
- Document whether a site outage should restart all guests or only critical services.

Ceph data availability does not guarantee enough compute capacity to restart every
guest at one site.

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
- Both Corosync links are operational over separate physical paths.
- Exactly five Ceph monitors exist and all are in quorum.
- `occ1`/`occ2` monitor locations are `datacenter=occ`.
- `bocc1`/`bocc2` monitor locations are `datacenter=bocc`.
- `witness` is the tiebreaker at `datacenter=witness`.
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