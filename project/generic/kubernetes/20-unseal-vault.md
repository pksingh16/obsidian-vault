# Unseal Vault

**Where to execute:** On the **OPS/APPS/TVP Container**.

```bash
# Get Vault Credential
ansible-vault view ~/git/gdp-platform-config/r160a-stretched-ops/caas-config/ansible/group_vars/all/vault_secrets.yaml --vault-password-file ~/git/gdp-platform-config/r160a-stretched/caas-config/.vault
```

**Where to execute:** On the **OPS Container**.

```bash
kubectl exec -it vault-0 -n vault -- /bin/sh -c 'export VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=<VALUE> VAULT_SKIP_VERIFY=true && vault operator unseal <VALUE>'
```