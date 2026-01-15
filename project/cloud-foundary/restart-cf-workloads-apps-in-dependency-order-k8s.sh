#!/usr/bin/env bash

NAMESPACE="cf-workloads"

# -----------------------------
# GROUP 1: GDP Applications
# -----------------------------
GDP_APPS=(
"gdp-registry"
"prmgr-sp"
"i18n-sp"
"loginterceptor-sp"
"logmgr-sp"
"dtm-sp"
"amgr-sp"
"logmgr"
"sechub-sp"
"umgr"
"smgr"
"lmgr-sp"
"lmgr"
"cad"
"sysst-sp"
"sysst"
"ej-sp"
"ej"
"dashboard-ui"
"dashboard-sp"
"polmgr"
"alarmmgr-sp"
"preferences-sp"
"simulation-manager-sp"
"record-manager-sp"
"playback-manager-sp"
"training-manager-sp"
"monmgr-sp"
"notification-sp"
"calendar-manager-sp"
"ui-toolkit"
"alarmmgr-mfe"
"jsch-sp"
"jsch"
)

# -----------------------------
# GROUP 2: IDS Applications
# -----------------------------
IDS_APPS=(
"ids-schema-registry-du"
"ids-config-server-sp"
"ids-business-config-manager-sp"
"ids-equipment-manager-sp"
"ids-alarm-manager-proxy-sp"
"alvea-showcase-ui"
"ids-histo-rest-api-sp"
"ids-histo-consumer-sp"
"ids-synoptic-sp"
"ids-command-executor-sp"
"ids-action-chain-manager-sp"
"ids-notification-sp"
"ids-alert-receiver-sp"
"ids-responsability-manager-sp"
"ids-permission-checker-sp"
"ids-trends-sp"
"ids-reports-sp"
"ids-procedure-information-sp"
"ids-assets-server"
"prometheus"
"ids-data-migration-sp"
)

# -----------------------------
# GROUP 3: CCTV Applications
# -----------------------------
CCTV_APPS=(
"cctv-configuration"
"cctv-camera"
"cctv-display"
"cctv-gateway"
"cctv-webdqm-ui"
"tvs-edge-proxy"
"vms-automation-scheduler"
"vms-edge-proxy-ui"
"vms-showcase-ui"
"cctv-multimedia"
)

wait_for_ready() {
  app="$1"
  echo "Waiting for $app to become Ready..."

  while true; do
    # Get NEWEST pod matching app name
    newpod=$(kubectl get pods -n "$NAMESPACE" \
      | grep "$app" \
      | awk '{print $1}' \
      | head -n 1)

    if [ -z "$newpod" ]; then
      echo "⏳ Pod not created yet... waiting"
      sleep 2
      continue
    fi

    # Check if ALL containers Ready=true
    ready=$(kubectl get pod "$newpod" -n "$NAMESPACE" \
      -o jsonpath='{range .status.containerStatuses[*]}{.ready}{" "}{end}')

    echo "Pod $newpod ready states: $ready"

    if echo "$ready" | grep -q "false"; then
      sleep 2
      continue
    fi

    echo "✔ $app Ready"
    break
  done
}

restart_group() {
  group_name="$1"
  shift
  apps=("$@")

  echo
  echo "============================================"
  echo " Restarting $group_name Applications"
  echo "============================================"

  for app in "${apps[@]}"; do
    echo "-------------------------------------------"
    echo "Restarting pods matching: $app"

    pods=$(kubectl get pods -n "$NAMESPACE" \
      | grep "$app" \
      | awk '{print $1}')

    if [ -z "$pods" ]; then
      echo "No pods found for $app"
    else
      for p in $pods; do
        echo "Deleting pod: $p"
        kubectl delete pod "$p" -n "$NAMESPACE"
      done
    fi

    sleep 2
    wait_for_ready "$app"
  done
}

# Run in order
restart_group "GDP" "${GDP_APPS[@]}"
restart_group "IDS" "${IDS_APPS[@]}"
restart_group "CCTV" "${CCTV_APPS[@]}"

echo "============================================"
echo "✔ All Restart Groups Complete"
echo "============================================"
