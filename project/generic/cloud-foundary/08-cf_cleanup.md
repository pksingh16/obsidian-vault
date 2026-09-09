# Cloud Foundry Cleanup (Non-Proxmox)

## Activate Org and Space in CF

```bash
#!/bin/bash
ORG="r160a"
SPACE="stable"

echo "Targeting org: $ORG, space: $SPACE ..."
cf target -o "$ORG" -s "$SPACE"
```

## List all apps in the space

```bash
echo "==== LISTING APPS ===="
cf apps
```

## List all services in space

```bash
echo "==== LISTING SERVICES ===="
cf services
```

## Delete space and org

```bash
echo "==== DELETING SPACE: $SPACE IN ORG: $ORG ===="
cf delete-space "$SPACE" -o "$ORG" -f
cf delete-org "$ORG" -f
```

## Delete services one by one

```bash
echo "==== DELETING ALL SERVICES ===="
for SERVICE in $(cf services | awk 'NR>4 {print $1}'); do
  echo "Deleting service: $SERVICE ..."
  cf delete-service "$SERVICE" -f
done
```

## Delete apps one by one

```bash
echo "==== DELETING ALL APPS ===="
for APP in $(cf apps | awk 'NR>4 {print $1}'); do
  echo "Deleting app: $APP ..."
  cf delete "$APP" -f -r
done
```

## Final list after delete

```bash
echo "==== FINAL LIST AFTER DELETION ===="
cf apps
cf services

echo "✅ Cleanup complete."
```
