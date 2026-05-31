SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

CREATE   PROCEDURE dbo.usp_Stop_VLDB_Rebuild_At_Window_End
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
          @SessionID int
        , @SQL nvarchar(100);

    SELECT TOP (1)
        @SessionID = r.session_id
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID
      AND t.text LIKE '%ALTER INDEX%'
      AND t.text LIKE '%REBUILD%'
    ORDER BY r.start_time;

    IF @SessionID IS NOT NULL
    BEGIN
        SET @SQL = N'KILL ' + CONVERT(nvarchar(20), @SessionID) + N';';
        EXEC sys.sp_executesql @SQL;
    END;

    UPDATE dbo.LargeDB_IndexMaintenanceWorkQueue
    SET
          Status = 'STOPPED'
        , EndTime = SYSDATETIME()
        , Message = 'VLDB REBUILD stopped automatically because the Sunday midnight maintenance window ended.'
    WHERE Status = 'RUNNING'
      AND RecommendedAction = 'REBUILD_PARTITION';

    EXEC msdb.dbo.sp_update_job
          @job_name = N'DBA - VLDB REBUILD - Active Log Backup - VLDB_WarehouseDB'
        , @enabled = 0;

    EXEC msdb.dbo.sp_update_job
          @job_name = N'DBA - VLDB REBUILD - Active Log Backup - VLDB_AppDB'
        , @enabled = 0;
END;

