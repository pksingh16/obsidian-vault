
# Fixing Rancher Apps Cluster not visible and says unavailable

```bash
kubectl -n cattle-system create configmap system-trusted-certificates   --from-file=ca-certificates.crt=/home/thales/rootca.crt   --dry-run=client -o yaml | kubectl apply -f -
```

# In case wrongly configured
```bash
kubectl -n cattle-system delete configmap system-trusted-certificates
```