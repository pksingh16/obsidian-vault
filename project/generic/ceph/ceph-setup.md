# Proxmox Ceph Stretch Cluster Runbook Index

Use one guide for the operation being performed. Do not combine cluster expansion,
server replacement, tiebreaker migration, or Cephx key rotation in one maintenance
window.

## Guides

| Scenario | Guide |
| --- | --- |
| Inspect production bonds, VLANs, and host IPs | [Production Proxmox and Ceph Network Configuration](ceph-network-configuration.md) |
| Build the complete cluster for the first time | [Deploy a Proxmox/Ceph Stretch Cluster from Scratch](ceph-stretch-cluster-from-scratch.md) |
| Add `occ3` and `bocc3` as OSD hosts | [Expand the Proxmox Ceph Stretch Cluster](ceph-cluster-expansion.md) |
| Replace the stretch witness with a different identity | [Replace a Ceph Stretch Tiebreaker](ceph-witness-replacement.md) |
| Select a failed-server procedure by node class | [Failed Server Replacement Index](ceph-server-replacement.md) |
| Replace `occ3` or `bocc3` | [Replace an OSD-Only Node](replace-osd-only-node.md) |
| Replace `occ1`, `occ2`, `bocc1`, or `bocc2` | [Replace an OSD + MON Node](replace-osd-mon-node.md) |
| Replace the MON-only `quorum` node | [Replace a Witness MON-Only Node](replace-witness-mon-node.md) |
| Rotate insecure Cephx keys and restrict ciphers | [Migrate Proxmox Cephx Keys](cephx-key-migration.md) |
| Inspect the active Ceph configuration | [Ceph Configuration](ceph-conf.md) |

## Target Topology

| Role | Servers |
| --- | --- |
| OCC OSD + MON nodes | `occ1`, `occ2` |
| OCC OSD-only node | `occ3` |
| BOCC OSD + MON nodes | `bocc1`, `bocc2` |
| BOCC OSD-only node | `bocc3` |
| Tiebreaker MON-only node | `quorum` |
| Total MONs | Five: two OCC, two BOCC, one tiebreaker |

The production network uses LACP `bond0`/VLAN-aware `vmbr0` on all nodes and LACP
`bond1`/VLAN-aware `vmbr1` for VLAN 118 on OCC/BOCC only. See the
[canonical network table](ceph-network-configuration.md) before configuring or
replacing any host.

`occ3` and `bocc3` are OSD hosts, not additional MON hosts. The tiebreaker's
`datacenter=witness` is a logical MON location and must not be created as an OSD
CRUSH datacenter bucket. Do not place OSDs on the tiebreaker. `quorum` can host VMs,
but its only Ceph daemon is its MON and every VM disk resides on shared Ceph storage.

## Fixed Workload Assumptions

- The cluster hosts QEMU VMs only; it does not host Proxmox containers.
- Every VM disk is on shared Ceph storage. No VM depends on node-local storage.
- Proxmox storage replication is not used for these shared-Ceph VM disks.
- A replacement receives current Ceph configuration and credentials after joining;
  do not attempt to recover or preserve local Cephx daemon keys from failed hardware.

## Universal Safety Rules

- Use a maintenance window and current off-cluster backups.
- Fence a failed server before removing or reusing its hostname or IP addresses.
- Change one server, site, MON, or OSD at a time.
- Keep Proxmox and Ceph monitor quorum throughout the operation.
- Wait for recovery and `active+clean` PGs before starting the next change.
- Do not run `pveceph init` on a node joining an existing cluster.
- Do not disable stretch mode, inject an old monmap/CRUSH map, or use force/lost
  operations as routine recovery shortcuts.
- Preserve VM configuration, HA and affinity policy, storage restrictions, mappings,
  backup jobs, and monitoring before deleting a failed node.

## Emergency Stop Conditions

Stop immediately and make no further removal if:

- Proxmox quorum or Ceph MON quorum is lost or repeatedly changes.
- A PG becomes `inactive`, `incomplete`, `stale`, or `unknown`.
- Client I/O fails or latency exceeds the approved maintenance threshold.
- Another server, MON, OSD set, or complete site fails.
- Capacity reaches `nearfull`, `backfillfull`, or `full`.
- A replacement has clock skew, wrong package versions, wrong CRUSH placement,
  duplicate hostname/IP behavior, or unstable networking.

## References

- [Proxmox VE Ceph administration](https://pve.proxmox.com/pve-docs/chapter-pveceph.html)
- [Ceph stretch mode](https://docs.ceph.com/en/squid/rados/operations/stretch-mode/)
- [Ceph monitor addition and removal](https://docs.ceph.com/en/squid/rados/operations/add-or-rm-mons/)
