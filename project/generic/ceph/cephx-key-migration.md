# Migrate Proxmox Cephx Keys to Secure Ciphers

Use this only after topology changes, recovery, and backfill are complete. Insecure
Cephx-key warnings are independent of stretch mode and server replacement.

## Preconditions

- All Proxmox and Ceph nodes run supported, compatible package versions.
- All MONs are in quorum; OSDs are `up`/`in`; PGs are `active+clean`.
- No upgrade, topology change, recovery, or client migration is running.
- Every Proxmox, kernel, and external Ceph client supports `aes256k`.
- Current keyrings and `/etc/pve/ceph.conf` are backed up securely.

## Cluster-owned Service Keys

Run the dry-run from one Proxmox node:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys --rotate-cluster-keys
```

Resolve every reported blocker. If clean, apply the identical selection:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys \
  --rotate-cluster-keys --apply
```

Wait for keys and tickets to refresh, then inspect status:

```bash
/usr/share/pve-manager/migrations/pve-cephx-rotate-service-keys
pveceph auth status
ceph health detail
```

## Client Keys and Cipher Restriction

Do not disable `aes` while any client still uses an insecure key. Follow the helper's
current dry-run output to stage client keys, distribute them to every consumer,
restart or reconnect clients, confirm adoption, and only then restrict allowed and
creatable ciphers.

Never use `--force` to bypass a blocker. Keep topology recovery and key rotation in
separate maintenance windows so failures remain attributable and reversible.
