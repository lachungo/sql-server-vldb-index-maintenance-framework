BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - VLDB REBUILD - Weekend Orchestrator', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Starts VLDB REBUILD maintenance every Friday at 7 PM and runs until Sunday 12:30 AM using the latest queued RunID. AG-aware with integrated log backup assist.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run VLDB Index Maintenance Queue', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
SET NOCOUNT ON;

DECLARE
      @RunID uniqueidentifier
    , @StopAt datetime2(0)
    , @Now datetime2(0)
    , @Today date
    , @DaysUntilSunday int
    , @NotPrimaryDB sysname;

SET @Now = SYSDATETIME();
SET @Today = CAST(@Now AS date);

SELECT TOP (1)
    @RunID = RunID
FROM dbamaint.dbo.LargeDB_IndexMaintenanceWorkQueue
WHERE Status = ''QUEUED''
  AND RecommendedAction = ''REBUILD_PARTITION''
ORDER BY QueueCreateTime DESC;

IF @RunID IS NULL
BEGIN
    RAISERROR(''No queued VLDB REBUILD maintenance queue found.'', 16, 1);
    RETURN;
END;

-- AG-aware safety check
SELECT TOP (1)
    @NotPrimaryDB = DatabaseName
FROM
(
    SELECT DISTINCT DatabaseName
    FROM dbamaint.dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RunID = @RunID
      AND Status = ''QUEUED''
      AND RecommendedAction = ''REBUILD_PARTITION''
) d
WHERE ISNULL(sys.fn_hadr_is_primary_replica(d.DatabaseName), 0) <> 1;

IF @NotPrimaryDB IS NOT NULL
BEGIN
    INSERT INTO dbamaint.dbo.LargeDB_MaintenanceProgress
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
        @NotPrimaryDB,
        N''VLDB_REBUILD_AG_SKIP'',
        N''SKIPPED'',
        SYSDATETIME(),
        SYSDATETIME(),
        N''Weekend VLDB REBUILD skipped because this replica is not primary for database: '' + @NotPrimaryDB
    );

    RETURN;
END;

-- Stop target: upcoming Sunday 12:30 AM
-- 1900-01-07 was a Sunday.
SET @DaysUntilSunday =
    (7 - (DATEDIFF(DAY, CONVERT(date, ''19000107''), @Today) % 7)) % 7;

SET @StopAt =
    DATEADD
    (
        MINUTE,
        30,
        DATEADD(DAY, @DaysUntilSunday, CAST(@Today AS datetime2(0)))
    );

-- If somehow started after Sunday 12:30 AM, move to next Sunday.
IF @StopAt <= @Now
BEGIN
    SET @StopAt = DATEADD(DAY, 7, @StopAt);
END;

-- Pre-flight log backup assist
EXEC dbamaint.dbo.usp_VLDB_LogBackup_Assist_IfNeeded
      @DBName = N''VLDB_AppDB''
    , @MinLogDriveFreeGB = 1024
    , @LogUsedThresholdGB = 1024;

EXEC dbamaint.dbo.usp_VLDB_LogBackup_Assist_IfNeeded
      @DBName = N''VLDB_WarehouseDB''
    , @MinLogDriveFreeGB = 1024
    , @LogUsedThresholdGB = 1024;

INSERT INTO dbamaint.dbo.LargeDB_MaintenanceProgress
(
    DatabaseName,
    OperationType,
    Status,
    StartTime,
    Message
)
VALUES
(
    N''dbamaint'',
    N''VLDB_REBUILD_MAINTENANCE_START'',
    N''STARTED'',
    SYSDATETIME(),
    N''Weekend VLDB REBUILD maintenance started. Auto-selected RunID: ''
    + CONVERT(nvarchar(50), @RunID)
    + N''. StopAt: ''
    + CONVERT(nvarchar(30), @StopAt, 120)
);

EXEC dbamaint.dbo.usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto
      @RunID = @RunID
    , @MaxDOP = 4
    , @MaxDurationMinutes = 120
    , @RunRebuilds = 1
    , @RunReorgs = 0
    , @StopAt = @StopAt
    , @DelaySecondsBetweenItems = 30;

-- Post-run log backup assist
EXEC dbamaint.dbo.usp_VLDB_LogBackup_Assist_IfNeeded
      @DBName = N''VLDB_AppDB''
    , @MinLogDriveFreeGB = 1024
    , @LogUsedThresholdGB = 1024;

EXEC dbamaint.dbo.usp_VLDB_LogBackup_Assist_IfNeeded
      @DBName = N''VLDB_WarehouseDB''
    , @MinLogDriveFreeGB = 1024
    , @LogUsedThresholdGB = 1024;
', 
		@database_name=N'dbamaint', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'DBA - Friday 7 PM - VLDB REBUILD Weekend Window', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=32, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20260529, 
		@active_end_date=99991231, 
		@active_start_time=190000, 
		@active_end_time=235959, 
		@schedule_uid=N'132515a6-daea-4d9d-824a-44c26c2db892'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

