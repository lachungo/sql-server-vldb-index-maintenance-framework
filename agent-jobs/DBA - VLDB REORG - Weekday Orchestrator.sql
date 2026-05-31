BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - VLDB REORG - Weekday Orchestrator', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Runs VLDB REORGANIZE_PARTITION workload Sunday, Monday, and Tuesday at 7 PM. Thursday execution is triggered by DBA - VLDB Maintenance - Thursday Capture and Queue Build. Auto-selects latest queue RunID and stops at 7 AM.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run VLDB REORG Queue', 
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

/* Self-heal stale RUNNING REORG rows when this Agent job is no longer running */
IF NOT EXISTS
(
    SELECT 1
    FROM msdb.dbo.sysjobactivity ja
    JOIN msdb.dbo.sysjobs j
        ON ja.job_id = j.job_id
    WHERE j.name = N''DBA - VLDB REORG - Weekday Orchestrator''
      AND ja.start_execution_date IS NOT NULL
      AND ja.stop_execution_date IS NULL
)
BEGIN
    UPDATE q
    SET
          Status = ''QUEUED''
        , StartTime = NULL
        , EndTime = NULL
        , ExecutedAction = NULL
        , ErrorMessage = ''Auto-reset from stale RUNNING state because SQL Agent job was no longer active.''
    FROM dbamaint.dbo.LargeDB_IndexMaintenanceWorkQueue q
    WHERE q.Status = ''RUNNING''
      AND q.RecommendedAction = ''REORGANIZE_PARTITION'';
END;

DECLARE
      @RunID uniqueidentifier
    , @StopAt datetime2(0)
    , @Today date;

SELECT TOP (1)
    @RunID = RunID
FROM dbamaint.dbo.LargeDB_IndexMaintenanceWorkQueue
WHERE RecommendedAction = ''REORGANIZE_PARTITION''
  AND Status = ''QUEUED''
GROUP BY RunID
ORDER BY MAX(QueueCreateTime) DESC;

IF @RunID IS NULL
BEGIN
    RAISERROR(''No queued VLDB REORG maintenance queue found.'', 16, 1);
    RETURN;
END;

SET @Today = CAST(SYSDATETIME() AS date);
SET @StopAt = DATEADD(HOUR, 7, DATEADD(DAY, 1, CAST(@Today AS datetime2(0))));

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
    N''VLDB_REORG_MAINTENANCE_START'',
    N''STARTED'',
    SYSDATETIME(),
    N''VLDB REORG maintenance started. Auto-selected RunID: ''
    + CONVERT(nvarchar(50), @RunID)
    + N''. StopAt: ''
    + CONVERT(nvarchar(30), @StopAt, 120)
);

EXEC dbamaint.dbo.usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto
      @RunID = @RunID
    , @MaxDOP = 4
    , @MaxDurationMinutes = 720
    , @RunRebuilds = 0
    , @RunReorgs = 1
    , @StopAt = @StopAt
    , @DelaySecondsBetweenItems = 30;
', 
		@database_name=N'dbamaint', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'DBA - VLDB REORG - Sun Mon Wed Tue 7PM', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=15, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20260524, 
		@active_end_date=99991231, 
		@active_start_time=190000, 
		@active_end_time=235959, 
		@schedule_uid=N'0f0eeeda-d3a9-403c-b126-76bfe26dba1c'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

