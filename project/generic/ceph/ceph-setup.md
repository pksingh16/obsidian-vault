# Proxmox Ceph Stretch Cluster Expansion and Witness Replacement

This runbook expands OCC with `occ3`, expands BOCC with `bocc3`, and replaces the
failed `mon.witness` with `mon.quorum`.

For a new seven-node deployment, use
[[ceph-stretch-cluster-from-scratch|Proxmox and Ceph Stretch Cluster Deployment from Scratch]].

> [!IMPORTANT]
> `occ3` and `bocc3` are OSD hosts, not additional monitor hosts. Standard Ceph
> stretch mode uses two monitors at OCC, two at BOCC, and one tiebreaker monitor.
> Keep five monitors after the migration.

## Why `set_location` Returns `ENOENT`

Joining a Proxmox node and installing Ceph packages do not create a Ceph monitor.
`ceph mon set_location` only updates a monitor ID that already exists in the monmap.
Therefore, `ENOENT` is expected for `bocc3`, `occ3`, and `quorum` at the point shown.

For `occ3` and `bocc3`, assign their OSD CRUSH host buckets to the correct
datacenter. For `quorum`, create a monitor with its location supplied on first boot;
an enabled stretch cluster rejects a new monitor that starts without a location.

> [!CAUTION]
> Use a maintenance window and current backups. Change one component at a time and
> wait for every PG to return to `active+clean`. Do not purge Ceph, disable stretch
> mode, edit the monmap offline, or remove any existing OSD during this procedure.

## Target Topology

| Role | Before | After |
| --- | --- | --- |
| OCC data site | `occ1`, `occ2` | `occ1`, `occ2`, `occ3` |
| BOCC data site | `bocc1`, `bocc2` | `bocc1`, `bocc2`, `bocc3` |
| Tiebreaker | `witness` | `quorum` |
| Monitors | 2 OCC + 2 BOCC + 1 witness | 2 OCC + 2 BOCC + 1 witness |

## 1. Pre-change Checks and Backups

Run from a healthy existing monitor such as `occ1`:

```bash
mkdir -p /root/ceph-change-backup
chmod 700 /root/ceph-change-backup
date -Is | tee /root/ceph-change-backup/start-time.txt

pveversion -v | tee /root/ceph-change-backup/pveversion.txt
ceph versions | tee /root/ceph-change-backup/versions.txt
ceph -s | tee /root/ceph-change-backup/status-before.txt
ceph health detail | tee /root/ceph-change-backup/health-before.txt
ceph quorum_status -f json-pretty | tee /root/ceph-change-backup/quorum-before.json
ceph mon dump -f json-pretty | tee /root/ceph-change-backup/mon-dump-before.json
ceph osd tree | tee /root/ceph-change-backup/osd-tree-before.txt
ceph osd crush tree | tee /root/ceph-change-backup/crush-tree-before.txt
ceph osd crush rule dump | tee /root/ceph-change-backup/crush-rules-before.json
ceph osd pool ls detail | tee /root/ceph-change-backup/pools-before.txt
ceph df | tee /root/ceph-change-backup/df-before.txt
ceph mon getmap -o /root/ceph-change-backup/monmap-before.bin
ceph osd getcrushmap -o /root/ceph-change-backup/crushmap-before.bin
cp -a /etc/pve/ceph.conf /root/ceph-change-backup/ceph.conf.before
cp -a /etc/pve/priv/ceph.mon.keyring /root/ceph-change-backup/
cp -a /etc/pve/priv/ceph.client.admin.keyring /root/ceph-change-backup/
chmod -R go-rwx /root/ceph-change-backup
```

Proceed only when:

- `occ1`, `occ2`, `bocc1`, and `bocc2` are in monitor quorum.
- All 225 PGs are `active+clean` and all 12 existing OSDs are `up` and `in`.
- The stretch rule places two replicas in `occ` and two in `bocc`.
- All nodes run compatible Proxmox and Ceph package versions.
- No recovery, backfill, key migration, or Ceph upgrade is running.
- The only unavailable monitor is the old `witness`.

The displayed Cephx cipher errors are separate from the failed witness. Do not combine
key rotation with this topology change. Section 10 addresses them after the topology
is stable.

## 2. Verify the New Nodes

Run on `occ3`, `bocc3`, and `quorum`:

```bash
apt install chrony -y
systemctl enable --now chrony
chronyc tracking
chronyc sources -v
hostname -s
getent hosts occ1 occ2 occ3 bocc1 bocc2 bocc3 quorum
```

Test the Ceph public network between every new node and all monitors. Test the Ceph
cluster network between `occ3`/`bocc3` and the existing OSD nodes:

```bash
ping -c 5 <peer_ceph_ip>
ping -M do -s 1472 -c 5 <peer_ceph_ip>  # IPv4 with MTU 1500
```

For MTU 9000, use a payload of `8972`. Ensure firewalls permit monitor TCP 3300 and
6789 and OSD TCP 6800-7568. Keep Ceph traffic separate from Corosync where possible.

Confirm the shared Proxmox Ceph configuration is available on each new node:

```bash
readlink -f /etc/ceph/ceph.conf
test -r /etc/pve/ceph.conf
test -r /etc/pve/priv/ceph.client.admin.keyring
ceph -s
```

Do not run `pveceph init` again. `/etc/pve/ceph.conf` is already distributed through
the Proxmox cluster filesystem.

## 3. Add `occ3` as an OCC OSD Host

From an existing monitor, create and place the empty host bucket before adding OSDs:

```bash
ceph osd crush add-bucket occ3 host
ceph osd crush move occ3 datacenter=occ
ceph osd crush tree
```

The output must show `host occ3` below `datacenter occ`. Stop and correct it if the
host appears below the root or another site.

On `occ3`, identify each empty OSD disk carefully and install the matching Ceph
packages if this was not already completed:

```bash
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
pveceph install
```

Create one OSD per verified raw data disk. This destroys the selected disk:

```bash
pveceph osd create /dev/<occ3_osd_disk_1>
# Repeat for each verified empty OSD disk.
```

Monitor from `occ1`:

```bash
watch -n 5 'ceph -s; ceph progress'
```

Wait for all PGs to become `active+clean`, then verify placement:

```bash
ceph osd tree
ceph osd df tree
ceph osd crush tree
```

## 4. Add `bocc3` as a BOCC OSD Host

Start only after the `occ3` change is clean. From an existing monitor:

```bash
ceph osd crush add-bucket bocc3 host
ceph osd crush move bocc3 datacenter=bocc
ceph osd crush tree
```

On `bocc3`:

```bash
lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
pveceph install
pveceph osd create /dev/<bocc3_osd_disk_1>
# Repeat for each verified empty OSD disk.
```

Again wait for all PGs to return to `active+clean`:

```bash
watch -n 5 'ceph -s; ceph progress'
ceph osd tree
ceph osd df tree
```

Keep usable capacity and OSD count as symmetrical as practical between OCC and BOCC.
A four-copy stretch pool is constrained by the site with less usable capacity.

## 5. Prepare the New Tiebreaker `quorum`

The tiebreaker should run a monitor only. Do not create OSDs on it and do not create a
`witness` datacenter bucket in the OSD CRUSH tree. Its monitor location is a logical
third location, different from `occ` and `bocc`.

### Names Used in This Procedure

| Name | Meaning |
| --- | --- |
| `quorum` | The hostname of the new Proxmox server |
| `mon.quorum` | The Ceph monitor ID hosted by that server |
| `ceph-mon@.service` | The systemd template supplied by the Ceph package; do not edit it |
| `ceph-mon@quorum.service` | The concrete local systemd service that runs `mon.quorum` |
| `datacenter=witness` | The logical Ceph MON location; it does not create an OSD CRUSH bucket |

Every command in this section runs in a root shell **on the new server named
`quorum`**. No command in this section runs on `occ1`, `bocc1`, or the old `witness`.

First inspect the packages, cluster access, and vendor systemd template:

```bash
# Host: quorum
pveceph install
ceph -s
systemctl cat ceph-mon@.service
```

`systemctl cat ceph-mon@.service` only displays the vendor template. It does not
start a monitor and must not be edited directly.

`pveceph mon create` currently has no monitor-location option. Before creating the
monitor, add a systemd override so its first boot includes Ceph's required location.
Create the directory and file explicitly; an empty `systemctl edit` session does not
write an override:

```bash
# Host: quorum
install -d -m 0755 /etc/systemd/system/ceph-mon@quorum.service.d
nano /etc/systemd/system/ceph-mon@quorum.service.d/override.conf
```

The directory and file exist only on the new `quorum` server. The file overrides only
`ceph-mon@quorum.service`; it does not change any existing monitor service.

For the Proxmox/Ceph Tentacle unit whose base command is
`/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph`, save exactly:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph --set-crush-location datacenter=witness
```

If the installed base `ExecStart` differs, preserve all of its arguments and append
only `--set-crush-location datacenter=witness`.

Reload systemd and check the effective unit:

```bash
# Host: quorum
systemctl daemon-reload
systemctl cat ceph-mon@quorum.service
systemctl show ceph-mon@quorum.service -p ExecStart
systemd-analyze verify ceph-mon@quorum.service
```

`systemctl cat` must display
`/etc/systemd/system/ceph-mon@quorum.service.d/override.conf`, and the effective
`ExecStart` must end with `--set-crush-location datacenter=witness`. Warnings from
`systemd-analyze verify` about `ceph-volume@.service` using `KillMode=none` are
unrelated to this monitor override.

Do not run `ceph mon set_location quorum ...` yet. `mon.quorum` does not exist, and
stretch mode requires the location when it first attempts to join.

## 6. Create `mon.quorum`

Choose exactly one path below.

### Path A: `pveceph mon create` Has Never Been Run

Run this only for a fresh attempt after the override in Section 5 has been verified:

```bash
# Host: quorum
pveceph mon create --mon-address <quorum_ceph_public_ip>
```

Do not use `--mon-addr`; it is not the current `pveceph` option. Do not run this command
on `occ1`; the command creates a local monitor data directory and service on the host
where it is executed.

### Path B: Current Recovery After the Failed First Attempt

Use this path for the state shown in the captured output: `pveceph mon create` already
completed, `ceph-mon@quorum.service` is stopped, and committed `ceph mon dump` does
not contain `mon.quorum`.

Do **not** run `pveceph mon create` again. On `quorum`, confirm that its local monitor
store exists, then start the already-created instance using the verified override:

```bash
# Host: quorum
test -d /var/lib/ceph/mon/ceph-quorum \
   && echo "monitor store exists" \
   || echo "STOP: monitor store is missing"

systemctl daemon-reload
systemctl reset-failed ceph-mon@quorum.service
systemctl start ceph-mon@quorum.service
systemctl status ceph-mon@quorum.service --no-pager
journalctl -u ceph-mon@quorum.service -b -o short-iso-precise --no-pager \
   | grep -vE 'Scheduled restart job|Start request repeated too quickly'
tail -n 200 /var/log/ceph/ceph-mon.quorum.log
```

`systemctl start ceph-mon@quorum.service` starts only `mon.quorum` on the new server.
It does not restart the four data-site monitors or the old witness.

Messages about `Start request repeated too quickly` only report systemd's restart
limit; they are not the original Ceph error. Read earlier journal entries and
`/var/log/ceph/ceph-mon.quorum.log` before retrying. Warnings about
`ceph-volume@.service` and `KillMode=none` are also unrelated.

### Verify the New Monitor from an Existing Monitor

After completing Path A or Path B, switch to a root shell on **`occ1`**. These commands
query the committed cluster state; they do not create or start services:

```bash
# Host: occ1
watch -n 5 'ceph -s; ceph mon stat'
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
```

The temporary expected state is six monitor entries: the four existing data-site
monitors, new `quorum`, and old `witness`. If the old witness remains healthy, all six
can temporarily be up; if it has failed, five can be up. If `quorum` does not join,
do not remove anything. Return to the new `quorum` server and inspect its local
service and the local monitor store's bootstrap map:

```bash
# Host: quorum
systemctl status ceph-mon@quorum.service --no-pager -l
journalctl -u ceph-mon@quorum.service -b -o short-iso-precise --no-pager \
   | grep -vE 'Scheduled restart job|Start request repeated too quickly'
tail -n 200 /var/log/ceph/ceph-mon.quorum.log
stat -c '%U:%G %a %n' /var/lib/ceph/mon/ceph-quorum \
   /var/lib/ceph/mon/ceph-quorum/keyring
ceph-mon -i quorum --extract-monmap /tmp/quorum-store-monmap
monmaptool --print /tmp/quorum-store-monmap
```

After it joins, reassert and verify its stored location from `occ1`:

```bash
# Host: occ1
ceph mon set_location quorum datacenter=witness
ceph mon dump -f json-pretty
```

At this point, `ceph health detail` can temporarily report:

```text
MON_CRUSH_LOC_STRETCH_MODE 1 monitor(s) have nonexistent CRUSH location
CRUSH location witness does not exist
```

This is expected specifically for `mon.quorum` while `mon.witness` is still the
configured tiebreaker. The logical third location must not be created in the OSD
CRUSH tree. Ceph exempts the current tiebreaker from this check, but `quorum` does
not receive that exemption until the tiebreaker is switched. Do not try to clear the
warning by creating a `witness` CRUSH bucket.

If the daemon still stops, do not delete its monitor directory and do not rerun
`pveceph mon create`. Preserve the journal output for diagnosis. In particular, look
for an explicit stretch-location rejection, address conflict, authentication error,
or connectivity failure to TCP 3300/6789 on the existing monitors.

## 7. Switch the Tiebreaker and Remove the Old Monitor

Only after `mon.quorum` is in the committed monmap and in quorum, run on `occ1`:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph mon set_new_tiebreaker quorum
ceph -s
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
```

The command argument is the monitor ID `quorum`, without the `mon.` prefix. Passing
`mon.quorum` is interpreted as `mon.mon.quorum` and returns `ENOENT`.

Before running `set_new_tiebreaker`, confirm that `mon.quorum` has
`datacenter=witness` in `ceph mon dump` and that `quorum` appears in `quorum_names`.
After running it, do not continue unless the committed map reports
`tiebreaker_mon quorum`, `quorum` remains in `quorum_names`, and the four data-site
monitors are still in quorum. `set_new_tiebreaker` does not remove the previous
tiebreaker.

After the switch, the nonexistent-location warning can temporarily refer to the old
`mon.witness`, because it is no longer exempt. Remove the old monitor only after all
of the checks above pass. The warning should clear after the old monitor is removed;
verify with `ceph health detail`.

Resolve any `clock skew detected on mon.quorum` warning before retiring the old
witness. Check the time service on `quorum` and compare its configured sources with a
healthy data-site monitor:

```bash
# Host: quorum
timedatectl status
systemctl status chrony.service --no-pager
chronyc tracking
chronyc sources -v
```

Do not continue until `ceph health detail` no longer reports clock skew for
`mon.quorum`.

If the old node can be recovered, run this on `witness`:

```bash
pveceph mon destroy witness
```

Then verify from `occ1`:

```bash
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

If the old node is permanently unavailable, run from `occ1`:

```bash
ceph mon remove witness
ceph mon dump -f json-pretty
ceph quorum_status -f json-pretty
ceph health detail
```

For the permanently unavailable case, also remove only the stale `[mon.witness]`
section and old witness address from `mon_host` in `/etc/pve/ceph.conf`. Keep another
backup first. Do not alter the FSID, networks, or healthy monitor entries:

```bash
cp -a /etc/pve/ceph.conf /root/ceph-change-backup/ceph.conf.before-witness-cleanup
nano /etc/pve/ceph.conf
```

Verify the final monitor membership:

```bash
ceph mon stat
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph -s
```

The monitor list must be exactly `occ1`, `occ2`, `bocc1`, `bocc2`, and `quorum`, with
all five in quorum.

## 8. Retire the Old Proxmox Node

Removing `mon.witness` does not remove the Proxmox node. Before deleting the node:

- Migrate or remove all VMs and containers from it.
- Remove it from HA groups, HA resources, and replication jobs.
- Confirm it owns no OSD, MGR, MDS, gateway, or other Ceph daemon.
- Confirm no storage is restricted to it and Corosync retains quorum without it.

On a surviving Proxmox node:

```bash
pvecm status
pvecm nodes
```

Power the old node off permanently, then run from a surviving node:

```bash
pvecm delnode witness
pvecm status
```

Never boot the removed node again while it retains its old cluster configuration.

## 9. Final Validation

```bash
ceph -s
ceph health detail
ceph mon stat
ceph quorum_status -f json-pretty
ceph mon dump -f json-pretty
ceph mgr stat
ceph osd tree
ceph osd df tree
ceph osd crush tree
ceph osd pool ls detail
ceph df
```

Confirm all of the following:

- Exactly five monitors exist and all are in quorum.
- `occ1`/`occ2` have monitor location `datacenter=occ`.
- `bocc1`/`bocc2` have monitor location `datacenter=bocc`.
- `quorum` has monitor location `datacenter=witness` and is the tiebreaker.
- `occ3` is below OCC and `bocc3` is below BOCC in the OSD CRUSH tree.
- All OSDs are `up` and `in`; all PGs are `active+clean`.
- Every pool still uses the intended stretch rule and has four replicas.

Save the final state:

```bash
ceph -s > /root/ceph-change-backup/status-after.txt
ceph quorum_status -f json-pretty > /root/ceph-change-backup/quorum-after.json
ceph mon dump -f json-pretty > /root/ceph-change-backup/mon-dump-after.json
ceph osd tree > /root/ceph-change-backup/osd-tree-after.txt
ceph osd getcrushmap -o /root/ceph-change-backup/crushmap-after.bin
```

## 10. Resolve the Cephx Cipher Errors Separately

The insecure-key errors in the supplied status are not caused by stretch mode or the
down witness. On current Proxmox VE 9, update all nodes to supported package versions
and complete required rolling service restarts. Then run the migration helper from
one node only.

Dry-run the cluster-owned service-key migration:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys --rotate-cluster-keys
```

If it reports no blocker, apply the same selection:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys \
      --rotate-cluster-keys --apply
```

Wait for rotating keys and tickets to refresh, then inspect the next steps:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys
pveceph auth status
ceph health detail
```

Do not rotate client keys or restrict ciphers until every Proxmox, kernel, and external
Ceph client supports `aes256k`. Follow the helper's dry-run output for staging client
keys, refreshing clients, confirming them, and restricting ciphers. Never use
`--force` to bypass a blocker.

## Stop and Rollback Conditions

Stop immediately if monitor quorum is lost, any PG becomes `inactive`, or client I/O
fails. Do not make another topology change while the cluster is in that state.

- Before removing `witness`, stop or remove a failed `mon.quorum` attempt and retain
   the original monitor membership.
- After switching the tiebreaker but before removing `witness`, switch it back only if
   the old monitor is healthy and in quorum.
- Adding OSDs causes data movement. Do not remove new OSDs as an immediate rollback;
   let recovery settle and use the standard safe OSD-removal process if needed.
- Never restore an old monmap or CRUSH map over a running cluster simply to undo these
   steps. Contact Proxmox or Ceph support if quorum cannot be restored normally.

## References

- [Proxmox VE Ceph administration](https://pve.proxmox.com/pve-docs/chapter-pveceph.html)
- [Ceph stretch mode](https://docs.ceph.com/en/squid/rados/operations/stretch-mode/)
- [Ceph monitor addition and removal](https://docs.ceph.com/en/squid/rados/operations/add-or-rm-mons/)
 