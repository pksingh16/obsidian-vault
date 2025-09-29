---
tags:
  - fetch-credentials
---
# GDP Apps Manager

**Where to execute:** On the **OPS/APPS/TVP Container** or on the **Jumpbox** virtual machine.

```bash
cat git/gdp-platform-config/r160a-stretched/paas-config/cf-for-k8s/cf-config.yml | grep "gdp"

# Sample Output:
# gdp_apps_manager_client_secret: <value>
```