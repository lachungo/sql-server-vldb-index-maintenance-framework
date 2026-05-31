SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

CREATE   PROCEDURE dbo.usp_Stop_VLDB_Reorg_At_Window_End
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID int;
    DECLARE @SQL nvarchar(100);

    SELECT TOP (1)
        @SessionID = r.session_id
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE t.text LIKE '%ALTER INDEX%'
      AND t.text LIKE '%REORGANIZE%'
      AND r.session_id <> @@SPID
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
        , Message = 'Weekday REORG window ended. REORG stopped automatically and will continue during the next weekday REORG window.'
    WHERE RecommendedAction = 'REORGANIZE_PARTITION'
      AND Status = 'RUNNING';

    INSERT INTO dbo.LargeDB_MaintenanceProgress
    (
          DatabaseName
        , OperationType
        , Status
        , StartTime
        , EndTime
        , Message
    )
    VALUES
    (
          N'dbamaint'
        , N'VLDB_REORG_WINDOW_STOP'
        , N'SUCCESS'
        , SYSDATETIME()
        , SYSDATETIME()
        , CONCAT(N'Weekday REORG stop completed. Session killed: ', COALESCE(CONVERT(nvarchar(20), @SessionID), N'None'))
    );
END;

