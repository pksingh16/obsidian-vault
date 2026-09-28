# Failed Proxmox/Ceph Server Replacement Index

Select the guide matching the failed server's Ceph role. Each guide contains two
independent, end-to-end procedures: exact hostname/IP reuse and replacement with a
new hostname/IP scheme.

Before selecting a procedure, verify the host's LACP bonds, VLANs, and addresses in
[Production Proxmox and Ceph Network Configuration](ceph-network-configuration.md).
Proxmox cluster joins use VLAN 111 management; Ceph MON creation uses VLAN 117.

| Failed node class | Examples | Complete guide |
| --- | --- | --- |
| OSD-only data-site node | `occ3`, `bocc3` | [Replace an OSD-Only Node](replace-osd-only-node.md) |
| OSD + data-site MON node | `occ1`, `occ2`, `bocc1`, `bocc2` | [Replace an OSD + MON Node](replace-osd-mon-node.md) |
| MON-only witness/quorum node | `quorum` | [Replace a Witness MON-Only Node](replace-witness-mon-node.md) |

## What Is `RECOVERY_NODE`?

`RECOVERY_NODE` is a healthy, surviving Proxmox cluster member used as the
administrative control point during recovery. Commands labelled **Run on
RECOVERY_NODE** inspect or change the shared Proxmox/Ceph cluster; they do not run on
the failed server or on the not-yet-joined replacement.

For example, use `occ1` when replacing `occ3`, provided `occ1` is healthy. If `occ1`
is the failed node, select another healthy existing member such as `occ2`, `bocc1`,
or `bocc2`.

The selected recovery node must:

- Be an existing Proxmox member with working `pvecm` and `ceph` commands.
- Be in Proxmox and Ceph quorum.
- Have working access to `/etc/pve` and the shared Ceph configuration.
- Have stable management connectivity and synchronized time.
- Not be the failed node, the new replacement, or a host being maintained.

`RECOVERY_NODE` is only a runbook shell variable. It does not create a special
Proxmox or Ceph role and may be changed to another healthy member between sessions.

## Legend: Common Terms and Acronyms

| Term | Meaning |
| --- | --- |
| Ceph | Distributed storage system providing the cluster's shared VM storage. |
| Ceph public network | Network used by Ceph clients, MONs, and OSD front-side communication. |
| Ceph cluster network | Optional private network used mainly for OSD replication, recovery, and backfill. |
| Cephx | Ceph authentication system used by clients and daemons. |
| Corosync | Messaging and membership service used by the Proxmox cluster. |
| CRUSH | Ceph placement algorithm and topology map that determines where data replicas are stored. |
| Data site | One of the two storage locations in this cluster: OCC or BOCC. |
| Fence | Force a failed server off and prevent it from rejoining with stale state or duplicate identity. |
| HA | High Availability; Proxmox services that restart or relocate managed VMs after node failure. |
| MON | Ceph Monitor; maintains authoritative cluster maps and participates in Ceph quorum. |
| Monmap | Ceph map containing the configured MON identities, addresses, and stretch locations. |
| OSD | Object Storage Daemon; stores Ceph data on a physical disk or device. |
| PG | Placement Group; logical grouping Ceph uses to distribute and track stored objects. |
| Proxmox quorum | Majority agreement required for safe writes to the Proxmox cluster configuration. |
| PVE | Proxmox Virtual Environment. |
| QEMU VM | Hardware-virtualized guest managed by Proxmox; the only workload type used here. |
| RBD | RADOS Block Device; Ceph block storage used for VM disks. |
| Recovery node | Healthy existing node from which cluster-wide recovery commands are run. |
| Replacement node | Newly installed server that will assume the failed server's role. |
| Stretch cluster | Ceph cluster spanning OCC and BOCC, with a third-location witness MON. |
| Tiebreaker or witness | MON in the third logical location that resolves stretch-site quorum decisions; it stores no OSD data. |
| VMID | Numeric Proxmox identifier assigned to a VM. |
| `/etc/pve` | Proxmox cluster filesystem containing shared cluster and VM configuration. |
| `active+clean` | Healthy PG state: available, with all required replicas correctly placed. |
| `degraded` or `undersized` | PG has fewer healthy or available replicas than intended; expected temporarily after an OSD failure but must be monitored. |
| `safe-to-destroy` | Ceph check confirming an OSD can be removed without losing required data. |
| `pvecm` | Proxmox command-line tool for cluster membership and quorum. |
| `pveceph` | Proxmox command-line tool for installing and managing Ceph services. |

### Configuration and Evidence Files

| File or directory | Definition |
| --- | --- |
| `/etc/pve/` | Proxmox cluster filesystem (`pmxcfs`). Changes are shared among quorate cluster members; it is not an ordinary local directory. |
| `/etc/pve/datacenter.cfg` | Cluster-wide Proxmox options such as migration, console, fencing, and scheduling behavior. |
| `/etc/pve/storage.cfg` | Cluster storage definitions, credentials references, content types, and optional node restrictions. It does not contain VM disk data. |
| `/etc/pve/corosync.conf` | Corosync cluster membership, node IDs, communication links, and quorum configuration. Never copy an old version over the live cluster. |
| `/etc/pve/ha/` | Proxmox HA groups, rules, and managed-resource configuration. |
| `/etc/pve/jobs.cfg` | Cluster job definitions that may contain node-specific selections. |
| `/etc/pve/nodes/<node>/qemu-server/` | QEMU VM configuration files currently owned by a particular Proxmox node. |
| `/etc/pve/mapping/` | Cluster-wide PCI and USB resource mappings used by VM configurations. |
| `/etc/pve/firewall/` | Cluster, host, and guest firewall configuration and aliases. |
| `/etc/pve/ceph.conf` | Cluster-managed Ceph configuration, normally exposed to Ceph tools through `/etc/ceph/ceph.conf`. |
| `/etc/pve/priv/` | Protected Proxmox secrets and keyrings. Back up only when specifically required and keep the copy encrypted and access-restricted. |
| `/var/lib/ceph/` | Local Ceph daemon state. Never copy it from failed hardware to a replacement node. |
| `config-files.txt` | Generated list of failed-node QEMU configuration paths discovered during evidence capture. |
| `vm-list.txt` | Generated VMID list used by the VM inspection/recovery loops. Empty is acceptable only if the target node truly owned no VMs. |
| `qm-<VMID>.conf` | Generated readable snapshot of a VM's disks, NICs, tags, boot options, and other Proxmox settings. |
| `node-policy-references.txt` | Generated list of old-hostname references that may require reconciliation after replacement. |
| `crushmap.bin` | Binary backup of Ceph's CRUSH placement map for forensic rollback. Do not import it during routine node replacement. |
| `monmap.bin` | Binary backup of the Ceph monitor map, captured by MON-related procedures for forensic recovery. |

Do not combine procedures or add roles that the failed node did not have. In this
cluster:

- QEMU VMs are the only workloads; there are no Proxmox containers.
- Every VM disk is on shared Ceph storage.
- `occ3` and `bocc3` run OSDs but no MON.
- `occ1`, `occ2`, `bocc1`, and `bocc2` run OSDs and data-site MONs.
- `quorum` runs the tiebreaker MON but no OSD; it may host shared-Ceph VMs.
- New OSD/MON credentials come from the live cluster workflow. Never restore old
  per-daemon Cephx keys or `/var/lib/ceph` from failed hardware.

> [!DANGER]
> Fence the failed server before starting any guide. Stop all removals if Proxmox or
> Ceph quorum changes, another host/site fails, client I/O fails, a PG becomes
> `inactive`/`incomplete`/`stale`/`unknown`, or the replacement has a version,
> location, clock, identity, or network mismatch.
