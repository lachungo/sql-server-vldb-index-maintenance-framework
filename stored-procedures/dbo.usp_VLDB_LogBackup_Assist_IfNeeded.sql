SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

CREATE   PROCEDURE dbo.usp_VLDB_LogBackup_Assist_IfNeeded
      @DBName sysname
    , @LogUsedThresholdGB decimal(18,2) = 1024.00
    , @MinStagingDriveFreeGB decimal(18,2) = 600.00
    , @CleanupOlderThanHours int = 4
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
          @UsedLogGB decimal(18,2)
        , @UDriveFreeGB decimal(18,2)
        , @FileName nvarchar(4000)
        , @SQL nvarchar(max)
        , @DeleteBefore datetime;

    IF DB_ID(@DBName) IS NULL RETURN;

    IF ISNULL(sys.fn_hadr_is_primary_replica(@DBName),0) <> 1
        RETURN;

    SET @DeleteBefore = DATEADD(HOUR, -@CleanupOlderThanHours, GETDATE());

    EXEC master.dbo.xp_delete_file
          0,
          N'U:\Staging\',
          N'trn',
          @DeleteBefore,
          1;

    IF EXISTS
    (
        SELECT 1
        FROM sys.dm_exec_requests
        WHERE command IN ('BACKUP DATABASE','BACKUP LOG')
    )
        RETURN;

    SELECT
        @UsedLogGB =
            CAST(used_log_space_in_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2))
    FROM sys.dm_db_log_space_usage
    WHERE database_id = DB_ID(@DBName);

    IF ISNULL(@UsedLogGB,0) < @LogUsedThresholdGB
        RETURN;

    SELECT TOP (1)
        @UDriveFreeGB =
            CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS decimal(18,2))
    FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    WHERE vs.volume_mount_point = 'U:\';

    IF ISNULL(@UDriveFreeGB,0) <= @MinStagingDriveFreeGB
    BEGIN
        RAISERROR('U:\Staging free space is below safety threshold. VLDB log backup assist skipped.', 10, 1);
        RETURN;
    END;

    SET @FileName =
        N'U:\Staging\' + @DBName + N'_Emergency_LogBackup_' +
        CONVERT(char(8), GETDATE(), 112) + N'_' +
        REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '') + N'.trn';

    SET @SQL = N'BACKUP LOG ' + QUOTENAME(@DBName) + N'
TO DISK = N''' + @FileName + N'''
WITH COMPRESSION, CHECKSUM, STATS = 5;';

    EXEC sys.sp_executesql @SQL;
END;

