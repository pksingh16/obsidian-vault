# Cloud Foundry Org/Space Creation

```bash
# Create ORG
cf create-org r160a

# Create Space
cf create-space stable -o r160a

# Org-level roles
cf set-org-role admin r160a OrgManager
cf set-org-role admin r160a BillingManager
cf set-org-role admin r160a OrgAuditor

# Space-level roles
cf set-space-role admin r160a stable SpaceManager
cf set-space-role admin r160a stable SpaceDeveloper
cf set-space-role admin r160a stable SpaceAuditor
```