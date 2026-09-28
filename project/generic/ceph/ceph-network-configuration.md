z# Production Proxmox and Ceph Network Configuration

This file is the canonical network reference for the seven-node production platform.
Use it when deploying, expanding, or replacing a Proxmox/Ceph node. Confirm every
value against switch configuration, DNS, IPAM, and the live host before making a
change.

## Physical Connectivity and Bonds

Each OCC and BOCC server uses four 10 Gb/s SFP+ interfaces across two independent
switches in each network domain.

| Logical path | Physical interfaces | Switch paths | Mode | Bridge | Scope |
| --- | --- | --- | --- | --- | --- |
| Server Farm | `nic0` + `nic2` | Server Farm Switch 1 + 2 | LACP (`802.3ad`) | VLAN-aware `vmbr0` | All nodes |
| Storage | `nic1` + `nic3` | Storage Switch 1 + 2 | LACP (`802.3ad`) | VLAN-aware `vmbr1` | OCC and BOCC only |

The active bridges use `bridge-vlan-aware yes` and permit VLANs `2-4092`. The Witness
site has no dedicated Storage switches and no Ceph cluster VLAN 118. Its local
template may retain an unused `bond1`/`vmbr1`, but neither may carry a VLAN 118 host
address or Ceph backend traffic.

> [!IMPORTANT]
> Production uses LACP, not active-backup. Both physical switch ports in a bond must
> belong to one correctly configured multi-chassis LAG/MLAG pair. Do not enable
> `802.3ad` across independent switches unless the switching platform supports that
> shared port channel.

## Infrastructure VLANs

| VLAN | Purpose | Host interface | Bridge | Participants | Network |
| --- | --- | --- | --- | --- | --- |
| 111 | Proxmox management (`PMX_MGT`) | `vmbr0.111` | `bond0` / `vmbr0` | All nodes | `10.50.1.0/26` |
| 114 | Corosync / Proxmox cluster | `vmbr0.114` | `bond0` / `vmbr0` | All nodes | `10.50.1.192/26` |
| 115 | Proxmox migration | `vmbr0.115` | `bond0` / `vmbr0` | All nodes | `10.50.2.0/25` |
| 117 | Ceph public | `vmbr0.117` | `bond0` / `vmbr0` | All nodes | `10.50.3.0/25` |
| 118 | Ceph cluster/backend | `vmbr1.118` | `bond1` / `vmbr1` | OCC and BOCC only | `10.50.3.128/25` |
| 125 | Configuration and administration | `vmbr0.125` | `bond0` / `vmbr0` | All nodes | `10.50.7.64/26` |

The default gateway is `10.50.7.126` on VLAN 125. Configure only one default gateway
per host unless an approved policy-routing design requires otherwise.

VLAN 114 is the production Corosync network. VLAN 115 is the migration network; it is
not a second Corosync link. Physical resilience for VLAN 114 comes from the two-link
LACP bond and redundant Server Farm switches.

## VM-Tagged VLANs

These VLANs traverse VLAN-aware `vmbr0` and are assigned to individual VM vNICs. Their
absence as host subinterfaces does not mean they are unavailable.

| VLAN | Purpose | Termination |
| --- | --- | --- |
| 106 | NMS / Clock Workstation | Switch and VM |
| 113 | Load Balancer VMs | VM VLAN tag |
| 116 | TVI Services | Switch and VM |
| 119 | Kubernetes Management VMs | VM VLAN tag |
| 120 | Kubernetes Workload VMs | VM VLAN tag |
| 121 | OCC Cyber Ceph public | Switch and VM |
| 122 | OCC Cyber Ceph cluster | Switch and VM |
| 123 | BOCC Cyber Ceph public | Switch and VM |
| 124 | BOCC Cyber Ceph cluster | Switch and VM |

## Per-Host Address Assignment

| Site | Host | VLAN 111 Management | VLAN 114 Corosync | VLAN 115 Migration | VLAN 117 Ceph public | VLAN 118 Ceph cluster | VLAN 125 Admin |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OCC | `occ1` | `10.50.1.10/26` | `10.50.1.200/26` | `10.50.2.10/25` | `10.50.3.10/25` | `10.50.3.140/25` | `10.50.7.69/26` |
| OCC | `occ2` | `10.50.1.11/26` | `10.50.1.201/26` | `10.50.2.11/25` | `10.50.3.11/25` | `10.50.3.141/25` | `10.50.7.70/26` |
| OCC | `occ3` | `10.50.1.12/26` | `10.50.1.202/26` | `10.50.2.12/25` | `10.50.3.12/25` | `10.50.3.142/25` | `10.50.7.81/26` |
| BOCC | `bocc1` | `10.50.1.20/26` | `10.50.1.203/26` | `10.50.2.13/25` | `10.50.3.20/25` | `10.50.3.150/25` | `10.50.7.72/26` |
| BOCC | `bocc2` | `10.50.1.21/26` | `10.50.1.204/26` | `10.50.2.14/25` | `10.50.3.21/25` | `10.50.3.151/25` | `10.50.7.73/26` |
| BOCC | `bocc3` | `10.50.1.22/26` | `10.50.1.205/26` | `10.50.2.15/25` | `10.50.3.15/25` | `10.50.3.145/25` | `10.50.7.74/26` |
| Witness | `quorum` | `10.50.1.31/26` | `10.50.1.207/26` | `10.50.2.31/25` | `10.50.3.31/25` | Not configured | `10.50.7.118/26` |

> [!CAUTION]
> The observed `bocc3` Ceph-public address is `10.50.3.15/25`. It breaks the otherwise
> sequential BOCC pattern and might be mistaken for `10.50.3.22/25`. Preserve
> `10.50.3.15/25` during replacement unless the network source of truth formally
> confirms a correction. Verify it in live `/etc/network/interfaces`, DNS, IPAM,
> firewall policy, and monitoring before production use.

## Proxmox Interface Template

Verify the actual Linux interface names before applying this template. The example
uses the production logical names `nic0` through `nic3`. Replace every `<...>` value
with the selected host's address from the table. Use `ifreload -a` only with console
or out-of-band access because an incorrect bond, VLAN, or gateway can disconnect the
host.

OCC and BOCC nodes use this structure:

```text
auto lo
iface lo inet loopback

auto bond0
iface bond0 inet manual
	bond-slaves nic0 nic2
	bond-mode 802.3ad
	bond-miimon 100
	bond-xmit-hash-policy layer2+3

auto vmbr0
iface vmbr0 inet manual
	bridge-ports bond0
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 2-4092

auto vmbr0.111
iface vmbr0.111 inet static
	address <vlan111_address>

auto vmbr0.114
iface vmbr0.114 inet static
	address <vlan114_address>

auto vmbr0.115
iface vmbr0.115 inet static
	address <vlan115_address>

auto vmbr0.117
iface vmbr0.117 inet static
	address <vlan117_address>

auto vmbr0.125
iface vmbr0.125 inet static
	address <vlan125_address>
	gateway 10.50.7.126

auto bond1
iface bond1 inet manual
	bond-slaves nic1 nic3
	bond-mode 802.3ad
	bond-miimon 100
	bond-xmit-hash-policy layer2+3

auto vmbr1
iface vmbr1 inet manual
	bridge-ports bond1
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 2-4092

auto vmbr1.118
iface vmbr1.118 inet static
	address <vlan118_address>

source /etc/network/interfaces.d/*
```

For `quorum`, use the `bond0`/`vmbr0` portion for all active host networks and omit
`vmbr1.118`. An existing local standard may retain empty `bond1`/`vmbr1` definitions,
but do not assign VLAN 118, an IP address, or Ceph backend traffic to them.

After writing the file, validate syntax before reload:

```bash
ifquery --check -a
ifreload -a
ip -br address
ip route
```

## Proxmox and Ceph Address Use

| Operation | Address/network to use |
| --- | --- |
| Proxmox GUI, API, SSH, and `pvecm add` seed | VLAN 111 management address, normally `occ1` at `10.50.1.10` |
| Corosync ring traffic | VLAN 114 address |
| Proxmox live migration | VLAN 115 network `10.50.2.0/25` |
| `pveceph init --network` and MON addresses | VLAN 117 Ceph-public network `10.50.3.0/25` |
| `pveceph init --cluster-network` | VLAN 118 Ceph-cluster network `10.50.3.128/25` |
| OSD replication, recovery, and backfill | VLAN 118; OCC and BOCC only |
| Default route and administrative services | VLAN 125; gateway `10.50.7.126` |

## Host Network Validation

Run on the host being installed or replaced. These commands do not change networking:

```bash
hostname -s
ip -br link
ip -br address
ip route
cat /proc/net/bonding/bond0
bridge vlan show dev vmbr0
```

On OCC and BOCC nodes, also verify the Storage bond and bridge:

```bash
cat /proc/net/bonding/bond1
bridge vlan show dev vmbr1
ip address show dev vmbr1.118
```

On `quorum`, confirm VLAN 118 is absent rather than creating it:

```bash
! ip link show vmbr1.118 >/dev/null 2>&1
```

For each bond, confirm `Bonding Mode: IEEE 802.3ad`, both expected slaves, an active
aggregator, and healthy MII status. Verify the switch LAG, allowed VLANs, MTU, MAC
learning, and both physical links from the switch side.

Test each host-level network using its source address. Substitute a peer address from
the table:

```bash
ping -c 5 -I <local_vlan111_ip> <peer_vlan111_ip>
ping -c 100 -I <local_vlan114_ip> <peer_vlan114_ip>
ping -c 5 -I <local_vlan115_ip> <peer_vlan115_ip>
ping -c 5 -I <local_vlan117_ip> <peer_vlan117_ip>
ping -c 5 -I <local_vlan125_ip> <peer_vlan125_ip>

# OCC and BOCC only:
ping -c 5 -I <local_vlan118_ip> <peer_vlan118_ip>
```

Use the MTU payload approved for that VLAN: `1472` for IPv4 MTU 1500 or `8972` for
IPv4 MTU 9000. Do not assume all VLANs use the same MTU.
