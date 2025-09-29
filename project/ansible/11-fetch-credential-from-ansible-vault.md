---
tags:
  - fetch-credentials
---
# GDP Platform Commands

**Copyable command snippets** and a brief description of **where each command is executed**. You can save it as, for example, `ansible_k8s_commands.md`.

This document contains useful commands for interacting with the GDP platform, viewing Ansible Vault secrets, checking RKE2 configurations, and retrieving Ceph object store credentials. Each command snippet is copyable and includes the context of execution.

---

## 1. View Hashicorp Vault Secrets

> **Where to execute:** On the **OPS/APPS/TVP Container** on the **Jumpbox** virtual machine.

```bash
ansible-vault view ~/git/gdp-platform-config/r160a-stretched-ops/caas-config/ansible/group_vars/all/vault_secrets.yaml \
--vault-password-file ~/git/gdp-platform-config/r160a-stretched/caas-config/.vault
```

---

## 2. View TVP OPS Credentials

**Where to execute:** On the **OPS/APPS/TVP Container** on the **Jumpbox** virtual machine.

```bash
ansible-vault view ~/git/gdp-platform-config/r160a-stretched/caas-config/rke2/ansible/group_vars/all/vault.yaml \
--vault-password-file ~/git/gdp-platform-config/r160a-stretched/caas-config/.vault
```

---

## 3. Get PaaS Output

**Where to execute:** Only on the **APPS Container** on the **Jumpbox** virtual machine.

```bash
paas output
```
