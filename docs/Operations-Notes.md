# Operations Notes

## Queue Reset

Only reset queue rows after confirming that no VLDB maintenance job is actively running.

```sql
USE dbamaint;
GO

UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
SET Status = 'QUEUED',
    StartTime = NULL,
    EndTime = NULL,
    ExecutedAction = NULL,
    ErrorMessage = 'Manually reset after validation.'
WHERE Status = 'RUNNING';
```

## Monitoring

```sql
SELECT RecommendedAction, Status, COUNT(*) AS ItemCount,
       SUM(ISNULL(IndexSizeGB,0)) AS TotalGB
FROM dbo.LargeDB_IndexMaintenanceWorkQueue
GROUP BY RecommendedAction, Status
ORDER BY RecommendedAction, Status;
```

## Azure Backup Contention

For very large databases, REBUILD operations may increase transaction log pressure and contend with cloud backup processing. Investigate backup scheduling, VSS/shadow-copy options, native backup-to-URL alternatives, and log backup throughput before enabling aggressive REBUILD windows.
