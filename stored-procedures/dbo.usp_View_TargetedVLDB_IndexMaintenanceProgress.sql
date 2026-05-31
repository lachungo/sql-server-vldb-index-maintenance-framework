SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON


/*==============================================================================
  4. Progress Query Procedure
==============================================================================*/

CREATE   PROCEDURE dbo.usp_View_TargetedVLDB_IndexMaintenanceProgress
    @RunID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        RunID,
        WorkQueueID,
        QueueCreateTime,
        StartTime,
        EndTime,
        DatabaseName,
        SchemaName,
        TableName,
        IndexName,
        PartitionNumber,
        IndexSizeGB,
        BeforeFragmentationPercent,
        AfterFragmentationPercent,
        RecommendedAction,
        ExecutedAction,
        Status,
        AttemptCount,
        DATEDIFF(MINUTE, StartTime, ISNULL(EndTime, SYSDATETIME())) AS DurationMinutes,
        Message,
        ErrorMessage
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE @RunID IS NULL OR RunID = @RunID
    ORDER BY
        CASE Status
            WHEN 'RUNNING' THEN 1
            WHEN 'FAILED' THEN 2
            WHEN 'QUEUED' THEN 3
            WHEN 'SUCCESS' THEN 4
            ELSE 5
        END,
        IndexSizeGB DESC;
END;

