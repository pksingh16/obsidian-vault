# Replace a Ceph Stretch Tiebreaker

Use this guide to replace `mon.witness` with `mon.quorum` while stretch mode remains
enabled. Standard topology is two OCC MONs, two BOCC MONs, and one tiebreaker.

The tiebreaker's `datacenter=witness` is a logical MON location. Do not create a
`witness` bucket in the OSD CRUSH tree and do not place OSDs on the tiebreaker. The
Proxmox server may host VMs whose disks reside on shared Ceph storage; its only Ceph
daemon is the tiebreaker MON.

Production `quorum` uses LACP `bond0`/VLAN-aware `vmbr0` with management
`10.50.1.31/26`, Corosync `10.50.1.207/26`, migration `10.50.2.31/25`, Ceph public
`10.50.3.31/25`, and admin `10.50.7.118/26`. It has no Storage-switch path or VLAN
118. See [Production Network Configuration](ceph-network-configuration.md).

## 1. Pre-change Gates

From `occ1`, preserve and inspect state:

```bash
ceph -s
ceph health detail
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph mon getmap -o /root/monmap-before-witness-change.bin
cp -a /etc/pve/ceph.conf /root/ceph.conf.before-witness-change
```

Proceed only when the four data-site MONs are in quorum, PGs are `active+clean`, the
new server has matching package versions and synchronized time, and no second failure
or recovery operation exists.

## 2. Identity Options

A new name/IP, such as `quorum` at `10.50.3.31`, permits overlap while the old witness
remains online. Reusing `witness` and its old IP requires the old server to be fenced
and its MON removed from the committed monmap before the replacement starts. Never
allow duplicate hostname or IP ownership.

For same-name/IP replacement, keep `MON_ID=witness`; for a new identity:

```bash
MON_ID=quorum
MON_IP=10.50.3.31
```

Use `10.50.1.31` for Proxmox management/cluster join and `10.50.3.31` only for the
Ceph MON public address. Do not configure `10.50.3.31` as the Proxmox join seed.

## 3. Prepare the Replacement MON

Every command in this section runs on the replacement server. Install packages and
verify cluster access and time:

```bash
pveceph install
ceph -s
chronyc tracking
chronyc sources -v
systemctl cat ceph-mon@.service
```

`pveceph mon create` has no location option. Add an instance override before its first
start:

```bash
install -d -m 0755 "/etc/systemd/system/ceph-mon@$MON_ID.service.d"
nano "/etc/systemd/system/ceph-mon@$MON_ID.service.d/override.conf"
```

Save:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=witness
```

If the vendor `ExecStart` differs, retain its arguments and append only the location.
Verify the effective unit:

```bash
systemctl daemon-reload
systemctl cat "ceph-mon@$MON_ID.service"
systemctl show "ceph-mon@$MON_ID.service" -p ExecStart
systemd-analyze verify "ceph-mon@$MON_ID.service"
```

Warnings about `ceph-volume@.service` using `KillMode=none` are unrelated. Do not run
`ceph mon set_location` before the MON exists.

## 4. Create the MON

```bash
# Host: replacement tiebreaker
pveceph mon create --mon-address "$MON_IP"
```

If creation completed but the service failed, do not rerun it or delete the monitor
store. Verify the override, then recover the existing store:

```bash
test -d "/var/lib/ceph/mon/ceph-$MON_ID"
systemctl daemon-reload
systemctl reset-failed "ceph-mon@$MON_ID.service"
systemctl start "ceph-mon@$MON_ID.service"
systemctl status "ceph-mon@$MON_ID.service" --no-pager -l
journalctl -u "ceph-mon@$MON_ID.service" -b -o short-iso-precise --no-pager
tail -n 200 "/var/log/ceph/ceph-mon.$MON_ID.log"
```

`Start request repeated too quickly` is only systemd's retry limit; inspect earlier
Ceph errors.

## 5. Verify and Select the New Tiebreaker

On `occ1`:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

Confirm the new MON is committed, has `datacenter=witness`, and appears in
`quorum_names`. During overlap, a nonexistent CRUSH-location warning for the new MON
is expected because only the current tiebreaker is exempt. Do not create a CRUSH
bucket to clear it.

Select the new monitor using its ID without a `mon.` prefix:

```bash
ceph mon set_new_tiebreaker "$MON_ID"
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph -s
```

Confirm `tiebreaker_mon` equals the new ID, it remains in quorum, the four data-site
MONs remain in quorum, PGs remain clean, and no clock-skew warning exists. The warning
may temporarily move to the old witness.

## 6. Remove the Old Tiebreaker

If the old node is accessible:

```bash
# Host: old witness
pveceph mon destroy witness
```

If permanently unavailable:

```bash
# Host: occ1
ceph mon remove witness
```

For same-name replacement, remove the failed old `witness` MON before Section 3, then
create the replacement using `MON_ID=witness`; there is no `set_new_tiebreaker` name
change, but the replacement must join with `datacenter=witness` and return to quorum.

Verify:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
ceph -s
```

Expected: exactly five MONs, all in quorum, the selected tiebreaker in
`disallowed_leaders`, and no nonexistent-location or clock-skew warning.

## 7. Remove the Old Proxmox Membership

Removing a MON does not remove a Proxmox node. Recover workloads and policy first by
following [Replace a Witness MON-Only Node](replace-witness-mon-node.md). Once the old
server is fenced and empty:

```bash
# Host: surviving Proxmox member
pvecm status
pvecm nodes
pvecm delnode witness
pvecm status
```

Never boot the removed installation again while it retains old cluster state.

## Stop Conditions

Stop if quorum is lost, a PG becomes inactive/incomplete, client I/O fails, another
host/site fails, the new MON has the wrong location, or time/network stability is not
healthy. Never restore an old monmap over a running cluster merely to undo the change.
