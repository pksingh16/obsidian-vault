# Restart All Applications

```bash
#!/bin/bash

# Function to restart an app and wait until it is running
restart_app() {
    APP=$1
    echo "--------------------------------------------------"
    echo "Restarting $APP ..."
    cf restart "$APP"
}

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
"ids-technical-config-du"
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
"cctv-technical-config-du"
"cctv-multimedia"
)

# -----------------------------
# Function to restart all apps in a group
# -----------------------------
restart_group() {
    for APP in "$@"; do
        restart_app "$APP"
    done
}

echo "================= Restarting GDP Apps ================="
restart_group "${GDP_APPS[@]}"

echo "================= Restarting IDS Apps ================="
restart_group "${IDS_APPS[@]}"

echo "================= Restarting CCTV Apps ================="
restart_group "${CCTV_APPS[@]}"

echo "All applications restarted successfully ✅"

```
