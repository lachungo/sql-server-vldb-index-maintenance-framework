SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

/*==============================================================================
  Procedure: dbo.usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto

  Header Brief:
      Executes the persistent VLDB index maintenance work queue for either
      REBUILD_PARTITION or REORGANIZE_PARTITION workloads.

  Purpose:
      This is the execution/orchestration engine for the VLDB maintenance
      framework. It consumes rows from dbo.LargeDB_IndexMaintenanceWorkQueue,
      executes ALTER INDEX commands, updates queue state, supports restartable
      maintenance windows, and protects the platform with a hard disk-space
      safety stop.

  Execution Behavior:
      - REBUILD mode runs REBUILD_PARTITION items only.
      - REORG mode runs REORGANIZE_PARTITION items only.
      - REBUILDs are processed largest first.
      - REORGs are processed smallest first.
      - STOPPED and FAILED rows are eligible for retry.
      - Orphaned RUNNING rows are self-healed when no ALTER INDEX is active.
      - Stale QUEUED metadata is normalized before execution.
      - Before every index operation, F:\ and G:\ are checked.
      - If F:\ or G:\ free space falls below 1 TB, the procedure:
            1. Stops the orchestration loop.
            2. Marks active RUNNING queue rows as STOPPED.
            3. Sends a CRITICAL email alert.
            4. Raises an error and exits safely.

  Protected Volumes:
      F:\ = Data Volume
      G:\ = Log Volume

  Dependencies:
      dbo.LargeDB_IndexMaintenanceWorkQueue
      msdb.dbo.sp_send_dbmail
      sys.dm_os_volume_stats
      sys.dm_exec_requests
      sys.dm_exec_sql_text

  Called By:
      DBA - VLDB REORG - Weekday Orchestrator
      DBA - VLDB REBUILD - Weekend Orchestrator

==============================================================================*/

CREATE PROCEDURE [dbo].[usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto]
      @RunID uniqueidentifier
    , @MaxDOP int = 4
    , @MaxDurationMinutes int = 120
    , @RunRebuilds bit = 1
    , @RunReorgs bit = 0
    , @StopAt datetime2(0)
    , @DelaySecondsBetweenItems int = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
          @WorkQueueID bigint
        , @DatabaseName sysname
        , @SchemaName sysname
        , @TableName sysname
        , @IndexName sysname
        , @PartitionNumber int
        , @RecommendedAction varchar(50)
        , @Command nvarchar(max)
        , @Delay varchar(20)
        , @DriveRows nvarchar(max)
        , @Body nvarchar(max)
        , @Subject nvarchar(400)
        , @BreachText nvarchar(max)
        , @ThresholdGB decimal(18,2) = 1024.00;

    ---------------------------------------------------------------------
    -- Self-heal orphaned RUNNING rows only when no ALTER INDEX is active
    ---------------------------------------------------------------------
    UPDATE q
    SET
          Status = 'STOPPED'
        , EndTime = SYSDATETIME()
        , Message = 'Self-healed orphaned RUNNING row. No active ALTER INDEX session was found. Eligible for next run.'
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue q
    WHERE q.RunID = @RunID
      AND q.Status = 'RUNNING'
      AND NOT EXISTS
      (
          SELECT 1
          FROM sys.dm_exec_requests r
          CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
          WHERE r.session_id <> @@SPID
            AND t.text LIKE '%ALTER INDEX%'
            AND (t.text LIKE '%REBUILD%' OR t.text LIKE '%REORGANIZE%')
      );

    ---------------------------------------------------------------------
    -- Normalize stale QUEUED metadata
    ---------------------------------------------------------------------
    UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
    SET
          StartTime = NULL
        , EndTime = NULL
        , ExecutedAction = NULL
        , Message = 'Reset queued row metadata. Item is waiting for future execution.'
    WHERE RunID = @RunID
      AND Status = 'QUEUED'
      AND
      (
            StartTime IS NOT NULL
         OR EndTime IS NOT NULL
         OR ExecutedAction IS NOT NULL
      );

    SET @Delay =
        RIGHT('00' + CAST(@DelaySecondsBetweenItems / 3600 AS varchar(2)),2)
        + ':'
        + RIGHT('00' + CAST((@DelaySecondsBetweenItems % 3600) / 60 AS varchar(2)),2)
        + ':'
        + RIGHT('00' + CAST(@DelaySecondsBetweenItems % 60 AS varchar(2)),2);

    WHILE SYSDATETIME() < @StopAt
    BEGIN
        -----------------------------------------------------------------
        -- HARD SAFETY CHECK: F:\ or G:\ below 1 TB
        -----------------------------------------------------------------
        SET @DriveRows = NULL;
        SET @Body = NULL;
        SET @Subject = NULL;
        SET @BreachText = NULL;

        ;WITH DriveSpace AS
        (
            SELECT DISTINCT
                  vs.volume_mount_point AS Drive
                , CASE
                      WHEN vs.volume_mount_point = 'F:\' THEN 'Data Volume'
                      WHEN vs.volume_mount_point = 'G:\' THEN 'Log Volume'
                      ELSE 'Visibility Only'
                  END AS DrivePurpose
                , CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2)) AS FreeGB
                , CASE
                      WHEN vs.volume_mount_point IN ('F:\','G:\')
                       AND CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2)) < @ThresholdGB
                          THEN 'BREACHED'
                      WHEN vs.volume_mount_point IN ('F:\','G:\')
                          THEN 'OK'
                      ELSE 'INFO'
                  END AS Status
            FROM sys.master_files mf
            CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
        )
        SELECT
            @DriveRows =
                CAST
                (
                    (
                        SELECT
                              td = Drive, ''
                            , td = DrivePurpose, ''
                            , td = FORMAT(FreeGB, 'N2'), ''
                            , td = CASE
                                       WHEN Drive IN ('F:\','G:\')
                                           THEN FORMAT(@ThresholdGB, 'N2')
                                       ELSE 'N/A'
                                   END, ''
                            , td = Status, ''
                        FROM DriveSpace
                        ORDER BY
                            CASE Drive
                                WHEN 'C:\' THEN 1
                                WHEN 'D:\' THEN 2
                                WHEN 'F:\' THEN 3
                                WHEN 'G:\' THEN 4
                                WHEN 'U:\' THEN 5
                                ELSE 9
                            END
                        FOR XML PATH('tr'), TYPE
                    ) AS nvarchar(max)
                );

        ;WITH DriveSpace AS
        (
            SELECT DISTINCT
                  vs.volume_mount_point AS Drive
                , CASE
                      WHEN vs.volume_mount_point = 'F:\' THEN 'Data Volume'
                      WHEN vs.volume_mount_point = 'G:\' THEN 'Log Volume'
                  END AS DrivePurpose
                , CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2)) AS FreeGB
            FROM sys.master_files mf
            CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
            WHERE vs.volume_mount_point IN ('F:\','G:\')
        )
        SELECT
            @BreachText =
                STRING_AGG
                (
                      DrivePurpose
                    + N' ('
                    + Drive
                    + N') currently has only '
                    + CONVERT(nvarchar(30), FreeGB)
                    + N' GB free which is below the configured 1 TB VLDB maintenance safety threshold.',
                    N'<br/>'
                )
        FROM DriveSpace
        WHERE FreeGB < @ThresholdGB;

        IF @BreachText IS NOT NULL
        BEGIN
            UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
            SET
                  Status = 'STOPPED'
                , EndTime = SYSDATETIME()
                , Message = 'VLDB maintenance stopped because F or G drive free space dropped below 1 TB.'
            WHERE RunID = @RunID
              AND Status = 'RUNNING';

            SET @Subject =
                  N'| '
                + CONVERT(nvarchar(10), CAST(SYSDATETIME() AS date), 120)
                + N' | '
                + @@SERVERNAME
                + N' [PRIMARY]'
                + N' | CRITICAL - VLDB Maintenance Stopped - Disk Space Below 1 TB';

            SET @Body =
N'
<html>
<body style="font-family:Segoe UI, Arial, sans-serif; font-size:13px;">
<h1 style="color:#C00000;">CRITICAL - VLDB Maintenance Stopped | ' + @@SERVERNAME + N'</h1>

<p><b>Reason:</b></p>
<p>' + @BreachText + N'</p>

<p>The VLDB maintenance orchestrator automatically stopped itself to prevent uncontrolled database or transaction log growth during index maintenance operations.</p>

<h3>Drive Space Visibility</h3>
<table border="1" cellpadding="6" cellspacing="0">
<tr>
    <th>Drive</th>
    <th>Purpose</th>
    <th>Current Free Space GB</th>
    <th>Threshold GB</th>
    <th>Status</th>
</tr>
'
+ ISNULL(@DriveRows, N'<tr><td colspan="5">No Records Found</td></tr>')
+ N'
</table>

<p><b>Required Action:</b> Increase free space above 1 TB before resuming VLDB maintenance.</p>

<p>Generated On: ' + CONVERT(nvarchar(30), SYSDATETIME(), 120) + N'</p>
</body>
</html>';

            EXEC msdb.dbo.sp_send_dbmail
                  @profile_name = N'VLDB_AppDB System'
                , @recipients = N'dba-team@example.com'
                , @subject = @Subject
                , @body = @Body
                , @body_format = 'HTML';

            RAISERROR('VLDB maintenance stopped because F or G drive free space dropped below 1 TB.', 16, 1);
            RETURN;
        END;

        -----------------------------------------------------------------
        -- Existing active ALTER INDEX guard
        -----------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
            WHERE r.session_id <> @@SPID
              AND t.text LIKE '%ALTER INDEX%'
              AND (t.text LIKE '%REBUILD%' OR t.text LIKE '%REORGANIZE%')
        )
        BEGIN
            PRINT 'ALTER INDEX already running. Waiting before next check...';
            WAITFOR DELAY '00:01:00';
            CONTINUE;
        END;

        -----------------------------------------------------------------
        -- Select next eligible queue item
        -----------------------------------------------------------------
        SET @WorkQueueID = NULL;

        SELECT TOP (1)
              @WorkQueueID = WorkQueueID
            , @DatabaseName = DatabaseName
            , @SchemaName = SchemaName
            , @TableName = TableName
            , @IndexName = IndexName
            , @PartitionNumber = PartitionNumber
            , @RecommendedAction = RecommendedAction
        FROM dbo.LargeDB_IndexMaintenanceWorkQueue
        WHERE RunID = @RunID
          AND Status IN ('QUEUED','STOPPED','FAILED')
          AND
          (
                (@RunRebuilds = 1 AND RecommendedAction = 'REBUILD_PARTITION')
             OR (@RunReorgs = 1 AND RecommendedAction = 'REORGANIZE_PARTITION')
          )
        ORDER BY
            CASE RecommendedAction
                WHEN 'REBUILD_PARTITION' THEN 1
                WHEN 'REORGANIZE_PARTITION' THEN 2
                ELSE 3
            END,
            CASE WHEN RecommendedAction = 'REORGANIZE_PARTITION' THEN IndexSizeGB END ASC,
            CASE WHEN RecommendedAction = 'REBUILD_PARTITION' THEN IndexSizeGB END DESC,
            BeforeFragmentationPercent DESC;

        IF @WorkQueueID IS NULL
        BEGIN
            PRINT 'No eligible queued, stopped, or failed items.';
            BREAK;
        END;

        -----------------------------------------------------------------
        -- AG-aware guard per database/item
        -----------------------------------------------------------------
        IF ISNULL(sys.fn_hadr_is_primary_replica(@DatabaseName), 0) <> 1
        BEGIN
            INSERT INTO dbo.LargeDB_MaintenanceProgress
            (
                DatabaseName,
                OperationType,
                Status,
                StartTime,
                EndTime,
                Message
            )
            VALUES
            (
                @DatabaseName,
                N'VLDB_MAINTENANCE_AG_SKIP',
                N'SKIPPED',
                SYSDATETIME(),
                SYSDATETIME(),
                N'VLDB maintenance skipped because this replica is not primary for database: ' + @DatabaseName
            );

            UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
            SET
                  Status = 'STOPPED'
                , EndTime = SYSDATETIME()
                , Message = 'Skipped because this replica is not primary for the database. Eligible for retry on the primary replica.'
            WHERE WorkQueueID = @WorkQueueID;

            WAITFOR DELAY @Delay;
            CONTINUE;
        END;

        -----------------------------------------------------------------
        -- Integrated log backup assist before each index operation
        -----------------------------------------------------------------
        EXEC dbo.usp_VLDB_LogBackup_Assist_IfNeeded
              @DBName = @DatabaseName
            , @MinLogDriveFreeGB = 1024
            , @LogUsedThresholdGB = 1024;

        -----------------------------------------------------------------
        -- Build command
        -----------------------------------------------------------------
        IF @RecommendedAction = 'REBUILD_PARTITION'
        BEGIN
            SET @Command =
            N'USE ' + QUOTENAME(@DatabaseName) + N';
ALTER INDEX ' + QUOTENAME(@IndexName) + N'
ON ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N'
REBUILD PARTITION = ' + CAST(@PartitionNumber AS nvarchar(20)) + N'
WITH
(
    ONLINE = ON,
    RESUMABLE = ON,
    MAXDOP = ' + CAST(@MaxDOP AS nvarchar(10)) + N',
    SORT_IN_TEMPDB = OFF
);';
        END;
        ELSE
        BEGIN
            SET @Command =
            N'USE ' + QUOTENAME(@DatabaseName) + N';
ALTER INDEX ' + QUOTENAME(@IndexName) + N'
ON ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N'
REORGANIZE PARTITION = ' + CAST(@PartitionNumber AS nvarchar(20)) + N';';
        END;

        UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
        SET
              Status = 'RUNNING'
            , StartTime = SYSDATETIME()
            , EndTime = NULL
            , AttemptCount = ISNULL(AttemptCount,0) + 1
            , CommandText = @Command
            , ExecutedAction = @RecommendedAction
            , Message =
                CASE
                    WHEN Status = 'STOPPED'
                        THEN 'Maintenance command restarted after prior window stop.'
                    WHEN Status = 'FAILED'
                        THEN 'Maintenance command retry started after prior failure.'
                    ELSE 'Maintenance command started.'
                  END
            , ErrorNumber = NULL
            , ErrorMessage = NULL
        WHERE WorkQueueID = @WorkQueueID;

        BEGIN TRY
            EXEC sys.sp_executesql @Command;

            UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
            SET
                  Status = 'SUCCESS'
                , EndTime = SYSDATETIME()
                , Message = 'Maintenance completed successfully.'
            WHERE WorkQueueID = @WorkQueueID;
        END TRY
        BEGIN CATCH
            UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
            SET
                  Status = 'FAILED'
                , EndTime = SYSDATETIME()
                , ErrorNumber = ERROR_NUMBER()
                , ErrorMessage = ERROR_MESSAGE()
                , Message = 'Maintenance failed. Automation will continue to next eligible item.'
            WHERE WorkQueueID = @WorkQueueID;
        END CATCH;

        WAITFOR DELAY @Delay;
    END;
END;

