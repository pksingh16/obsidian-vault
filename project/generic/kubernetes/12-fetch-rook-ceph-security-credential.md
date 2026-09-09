---
tags:
  - fetch-credentials
---
# Retrieve CEPH Security Credentials

## Retrieve Ceph Object Store `AccessKey`

**Where to execute:** On a terminal with `kubectl` access to the `apps` cluster.

```bash
kubectl -n rook-ceph get secret rook-ceph-object-user-gdp-object-store-gdpadmin -o jsonpath='{.data.AccessKey}' | base64 --decode
```

---

## Retrieve Ceph Object Store `SecretKey`

**Where to execute:** On a terminal with `kubectl` access to the `apps` cluster.

```bash
kubectl -n rook-ceph get secret rook-ceph-object-user-gdp-object-store-gdpadmin -o jsonpath='{.data.SecretKey}' | base64 --decode
```

---
