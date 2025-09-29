# Fix Redis Issues

```bash
# How to Find the Helm Release:
helm list -n <your-namespace>

# Check which apps are bound to redis:
cf s | grep redis

#alvea-showcase-ui-redis                      redis        7-2-4      alvea-showcase-ui                                                                       create succeeded   minibroker
#cctv-camera-redis                            redis        7-2-4      cctv-camera                                                                             create succeeded   minibroker
#cctv-configuration-redis                     redis        7-2-4      cctv-configuration                                                                      create succeeded   minibroker
#cctv-display-redis-cache                     redis        7-2-4      cctv-display                                                                            create succeeded   minibroker
#cctv-multimedia-redis                        redis        7-2-4      cctv-multimedia                                                                         create failed      minibroker
#fas-ioc-redis                                redis        7-2-4      fas-ioc-cfg, fas-ioc-control, fas-ioc-north, fas-ioc-notifier                           create succeeded   minibroker
#fas-redis                                    redis        7-2-4      scs-subsystem-gw                                                                        create succeeded   minibroker
#gdp-redis                                    redis        7-2-4      alarmmgr-sp, cad, ej, jsch, lmgr, logmgr, polmgr, smgr, sysst, umgr                     create succeeded   minibroker
#ids-alarm-proxy-sp-redis                     redis        7-2-4      ids-alarm-manager-proxy-sp                                                              create succeeded   minibroker
#ids-alert-receiver-sp-redis                  redis        7-2-4      ids-alert-receiver-sp                                                                   create succeeded   minibroker
#ids-command-executor-sp-redis                redis        7-2-4      ids-command-executor-sp                                                                 create succeeded   minibroker
#ids-equipment-mgr-sp-redis                   redis        7-2-4      ids-equipment-manager-sp                                                                create succeeded   minibroker
#ids-redis-service                            redis        7-2-4      ids-action-chain-manager-sp, ids-histo-rest-api-sp, ids-responsability-manager-sp       create succeeded   minibroker
#ivv-redis-service                            redis        7-2-4                                                                                              create succeeded   minibroker
#redis-notification                           redis        7-2-4      ids-notification-sp                                                                     create succeeded   minibroker



# cf stop app bounded to redis commands:
cf stop alvea-showcase-ui
cf stop cctv-camera
cf stop cctv-configuration
cf stop cctv-display
for app in fas-ioc-cfg fas-ioc-control fas-ioc-north fas-ioc-notifier; do cf stop $app; done
cf stop scs-subsystem-gw
for app in alarmmgr-sp cad ej jsch lmgr logmgr polmgr smgr sysst umgr; do cf stop $app; done
cf stop ids-alarm-manager-proxy-sp
cf stop ids-alert-receiver-sp
cf stop ids-command-executor-sp
cf stop ids-equipment-manager-sp
for app in ids-action-chain-manager-sp ids-histo-rest-api-sp ids-responsability-manager-sp; do cf stop $app; done
cf stop ids-notification-sp
cf stop ivv-redis-service

# cf unbind-service commands:
cf unbind-service alvea-showcase-ui alvea-showcase-ui-redis
cf unbind-service cctv-camera cctv-camera-redis
cf unbind-service cctv-configuration cctv-configuration-redis
cf unbind-service cctv-display cctv-display-redis-cache
for app in fas-ioc-cfg fas-ioc-control fas-ioc-north fas-ioc-notifier; do cf unbind-service $app fas-ioc-redis; done
cf unbind-service scs-subsystem-gw fas-redis
for app in alarmmgr-sp cad ej jsch lmgr logmgr polmgr smgr sysst umgr; do cf unbind-service $app gdp-redis; done
cf unbind-service ids-alarm-manager-proxy-sp ids-alarm-proxy-sp-redis
cf unbind-service ids-alert-receiver-sp ids-alert-receiver-sp-redis
cf unbind-service ids-command-executor-sp ids-command-executor-sp-redis
cf unbind-service ids-equipment-manager-sp ids-equipment-mgr-sp-redis
for app in ids-action-chain-manager-sp ids-histo-rest-api-sp ids-responsability-manager-sp; do cf unbind-service $app ids-redis-service; done
cf unbind-service ids-notification-sp redis-notification

# cf delete-service commands:
cf delete-service alvea-showcase-ui-redis -f
cf delete-service cctv-camera-redis -f
cf delete-service cctv-configuration-redis -f
cf delete-service cctv-display-redis-cache -f
cf delete-service fas-ioc-redis -f
cf delete-service fas-redis -f
cf delete-service gdp-redis -f
cf delete-service ids-alarm-proxy-sp-redis -f
cf delete-service ids-alert-receiver-sp-redis -f
cf delete-service ids-command-executor-sp-redis -f
cf delete-service ids-equipment-mgr-sp-redis -f
cf delete-service ids-redis-service -f
cf delete-service redis-notification -f
cf delete-service ivv-redis-service -f
# Wait for all the redis-service to be deleted (can check in cf uaa console login under services filter redis)

# In case it doesnot purge things properly and cf s | grep redis ahows delete failed

######################################################################
for svc in $(cf services | grep redis | awk '{print $1}'); do
    guid=$(cf service $svc --guid)
    echo "Purging service: $svc, GUID: $guid"
    cf curl -X DELETE /v2/service_instances/$guid?purge=true
done
#######################################################################

# How to delete all Redis Helm releases except minibroker:
helm list -n minibroker -o json | jq -r '.[] | select(.name != "minibroker") | .name' | xargs -n1 -I{} helm uninstall {} -n minibroker

# Clean up PVCs after uninstall:
kubectl get pvc -n minibroker | grep redis | awk '{print $1}' | xargs -n1 -I{} kubectl delete pvc {} -n minibroker

# cf create-service commands:
cf create-service redis 7-2-4 alvea-showcase-ui-redis
cf create-service redis 7-2-4 cctv-camera-redis
cf create-service redis 7-2-4 cctv-configuration-redis
cf create-service redis 7-2-4 cctv-display-redis-cache
cf create-service redis 7-2-4 fas-ioc-redis
cf create-service redis 7-2-4 fas-redis
cf create-service redis 7-2-4 gdp-redis
cf create-service redis 7-2-4 ids-alarm-proxy-sp-redis
cf create-service redis 7-2-4 ids-alert-receiver-sp-redis
cf create-service redis 7-2-4 ids-command-executor-sp-redis
cf create-service redis 7-2-4 ids-equipment-mgr-sp-redis
cf create-service redis 7-2-4 ids-redis-service
cf create-service redis 7-2-4 redis-notification
cf create-service redis 7-2-4 ivv-redis-service
# Wait for all the redis-service to be created (can check in cf uaa console login under services filter redis)

# cf bind-service and cf start commands:
cf bind-service alvea-showcase-ui alvea-showcase-ui-redis
cf start alvea-showcase-ui

cf bind-service cctv-camera cctv-camera-redis
cf start cctv-camera

cf bind-service cctv-configuration cctv-configuration-redis
cf start cctv-configuration

cf bind-service cctv-display cctv-display-redis-cache
cf start cctv-display

for app in fas-ioc-cfg fas-ioc-control fas-ioc-north fas-ioc-notifier; do
  cf bind-service $app fas-ioc-redis
  cf start $app
done

cf bind-service scs-subsystem-gw fas-redis
cf start scs-subsystem-gw

for app in alarmmgr-sp cad ej jsch lmgr logmgr polmgr smgr sysst umgr; do
  cf bind-service $app gdp-redis
  cf start $app
done

cf bind-service ids-alarm-manager-proxy-sp ids-alarm-proxy-sp-redis
cf start ids-alarm-manager-proxy-sp

cf bind-service ids-alert-receiver-sp ids-alert-receiver-sp-redis
cf start ids-alert-receiver-sp

cf bind-service ids-command-executor-sp ids-command-executor-sp-redis
cf start ids-command-executor-sp

cf bind-service ids-equipment-manager-sp ids-equipment-mgr-sp-redis
cf start ids-equipment-manager-sp

for app in ids-action-chain-manager-sp ids-histo-rest-api-sp ids-responsability-manager-sp; do
  cf bind-service $app ids-redis-service
  cf start $app
done

cf bind-service ids-notification-sp redis-notification
cf start ids-notification-sp

```
