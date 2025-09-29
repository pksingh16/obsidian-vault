# Ceph RBD Cleanup (Non-Proxmox)

```bash
for vol in $(rbd ls -p R160A | grep csi-vol); do
  echo "Removing $vol..."
  rbd rm -p R160A $vol --no-progress
done
```