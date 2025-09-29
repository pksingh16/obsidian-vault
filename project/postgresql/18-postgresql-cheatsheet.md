# Login to PostgreSQL command line

Go to the postgresql pgha pod using k9s or Rancher shell in and run the following commands:

```bash
psql -U postgres -d postgres
SELECT oid, datname FROM pg_database;
```

```bash
# Get all database names based on its uid:
SELECT oid, datname FROM pg_database;
```

```bash
# Get postgresql database size sorted in ascending order:
du -sh /pgdata/pg13/base/* | sort -h
```

```bash
# Single Liner to go to the pod cli:
kubectl exec -n pgo -it <postgres-pgha1-4qd4-0> -c database -- psql -U postgres -d postgres
```

