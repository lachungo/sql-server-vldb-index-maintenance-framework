BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - VLDB Drive Space Monitor', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Disabled. Disk-space protection is now embedded directly inside VLDB REORG and REBUILD orchestrators. Remaining references are informational only.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Capture F and G Drive Space', 
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
INSERT INTO dbamaint.dbo.VLDB_DriveSpaceMonitor
(
      DriveLetter
    , VolumeName
    , TotalGB
    , FreeGB
    , FreePct
    , Status
)
SELECT
      vs.volume_mount_point
    , vs.logical_volume_name
    , CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2))
    , CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2))
    , CAST(vs.available_bytes * 100.0 / NULLIF(vs.total_bytes,0) AS decimal(10,2))
    , CASE
          WHEN vs.volume_mount_point = ''F:\''
               AND vs.available_bytes / 1024.0 / 1024 / 1024 < 1024
               THEN ''STOP - F DRIVE BELOW 1 TB''
          WHEN vs.volume_mount_point = ''F:\''
               AND vs.available_bytes / 1024.0 / 1024 / 1024 < 1536
               THEN ''WARNING - F DRIVE BELOW 1.5 TB''
          ELSE ''OK''
      END
FROM sys.database_files df
CROSS APPLY sys.dm_os_volume_stats(DB_ID(), df.file_id) vs
WHERE df.file_id IN (1,2);', 
		@database_name=N'VLDB_WarehouseDB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'DBA - VLDB Drive Space Monitor - Every 15 Minutes', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260515, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'811b1ad3-ba37-4944-b4ec-23f8840e63e5'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

