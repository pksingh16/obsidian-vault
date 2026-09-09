# CF Application Environment Variables

## Activate Org and Space in CF

```bash
ORG="r160a"
SPACE="stable"

echo "Targeting org: $ORG, space: $SPACE ..."
cf target -o "$ORG" -s "$SPACE"
```

## Get Environment Variables

```bash
cf env <application-name>
```

## Set Environment Variables

```bash
cf set-env <application-name> <ENV_VARIABLE> <ENVIRONMENT_VARIABLE_VALUE>
```
