SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

CREATE   PROCEDURE dbo.usp_Send_VLDB_MaintenanceProgressReport_Core
      @ProfileName sysname = N'VLDB_AppDB System'
    , @Recipients nvarchar(max)
    , @LookbackHours int = 168
    , @MaintenanceType varchar(20)
    , @CompletedTop int = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
          @Action varchar(50)
        , @Title nvarchar(200)
        , @Subject nvarchar(400)
        , @Body nvarchar(max)
        , @Now datetime2(0) = SYSDATETIME()
        , @SummaryRows nvarchar(max) = N''
        , @CompletedRows nvarchar(max) = N''
        , @RunningRows nvarchar(max) = N''
        , @QueuedRows nvarchar(max) = N''
        , @CompletedCount int = 0
        , @ProcessedGB decimal(18,2) = 0
        , @ProcessedTB decimal(18,2) = 0
        , @TotalDurationMinutes int = 0
        , @TotalDurationHours decimal(18,2) = 0
        , @AvgMinutesPerGB decimal(18,2) = 0
        , @RemainingGB decimal(18,2) = 0
        , @RemainingTB decimal(18,2) = 0
        , @LastGoodRunDate datetime2(0)
        , @LastGoodRunID uniqueidentifier
        , @ServerName sysname = @@SERVERNAME
        , @AGRole nvarchar(30) = N'PRIMARY';

    SET @Action =
        CASE UPPER(@MaintenanceType)
            WHEN 'REBUILD' THEN 'REBUILD_PARTITION'
            WHEN 'REORG'   THEN 'REORGANIZE_PARTITION'
        END;

    IF @Action IS NULL
    BEGIN
        RAISERROR('Invalid @MaintenanceType. Use REBUILD or REORG.',16,1);
        RETURN;
    END;

    SELECT TOP (1)
          @LastGoodRunID = RunID
        , @LastGoodRunDate = MAX(EndTime)
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status = 'SUCCESS'
      AND EndTime IS NOT NULL
    GROUP BY RunID
    ORDER BY MAX(EndTime) DESC;

    SET @Title =
        N'VLDB ' + UPPER(@MaintenanceType)
        + N' Weekly Progress Report | ' + @ServerName;

    SET @Subject =
        N'| ' + CONVERT(nvarchar(10), CAST(@Now AS date), 120)
        + N' | ' + @ServerName
        + N' [' + @AGRole + N']'
        + N' | VLDB ' + UPPER(@MaintenanceType)
        + N' Weekly Progress Report';

    SELECT
          @CompletedCount = COUNT(*)
        , @ProcessedGB = ISNULL(SUM(ISNULL(IndexSizeGB,0)),0)
        , @ProcessedTB = ISNULL(SUM(ISNULL(IndexSizeGB,0))/1024.0,0)
        , @TotalDurationMinutes = ISNULL(SUM(DATEDIFF(MINUTE, StartTime, EndTime)),0)
        , @TotalDurationHours = ISNULL(CAST(SUM(DATEDIFF(SECOND, StartTime, EndTime))/3600.0 AS decimal(18,2)),0)
        , @AvgMinutesPerGB =
            ISNULL(CAST(SUM(DATEDIFF(SECOND, StartTime, EndTime))/60.0 / NULLIF(SUM(ISNULL(IndexSizeGB,0)),0) AS decimal(18,2)),0)
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status = 'SUCCESS'
      AND RunID = @LastGoodRunID
      AND StartTime IS NOT NULL
      AND EndTime IS NOT NULL;

    SELECT
          @RemainingGB = ISNULL(SUM(ISNULL(IndexSizeGB,0)),0)
        , @RemainingTB = ISNULL(SUM(ISNULL(IndexSizeGB,0))/1024.0,0)
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status IN ('QUEUED','STOPPED','FAILED','RUNNING');

    SELECT @SummaryRows = ISNULL(@SummaryRows,N'') +
        N'<tr><td>' + Status + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(COUNT(*),'N0') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(SUM(ISNULL(IndexSizeGB,0)),'N2') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(SUM(ISNULL(IndexSizeGB,0))/1024.0,'N2') + N'</td></tr>'
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status IN ('SUCCESS','RUNNING','QUEUED','STOPPED','FAILED')
    GROUP BY Status
    ORDER BY
        CASE Status
            WHEN 'RUNNING' THEN 1
            WHEN 'FAILED' THEN 2
            WHEN 'STOPPED' THEN 3
            WHEN 'QUEUED' THEN 4
            WHEN 'SUCCESS' THEN 5
            ELSE 6
        END;

    SELECT TOP (@CompletedTop) @CompletedRows = ISNULL(@CompletedRows,N'') +
        N'<tr><td>' + DatabaseName + N'</td>' +
        N'<td>' + IndexName + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(IndexSizeGB,'N2') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(BeforeFragmentationPercent,'N2') + N'%</td>' +
        N'<td>' + ISNULL(ExecutedAction,N'') + N'</td>' +
        N'<td>' + Status + N'</td>' +
        N'<td>' + CONVERT(nvarchar(30), StartTime, 120) + N'</td>' +
        N'<td>' + CONVERT(nvarchar(30), EndTime, 120) + N'</td>' +
        N'<td style="text-align:right;">' + CAST(DATEDIFF(MINUTE, StartTime, EndTime) AS nvarchar(20)) + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(DATEDIFF(SECOND, StartTime, EndTime)/3600.0,'N2') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT((DATEDIFF(SECOND, StartTime, EndTime)/60.0)/NULLIF(IndexSizeGB,0),'N2') + N'</td></tr>'
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status = 'SUCCESS'
      AND RunID = @LastGoodRunID
      AND StartTime IS NOT NULL
      AND EndTime IS NOT NULL
    ORDER BY
        CASE WHEN @Action = 'REBUILD_PARTITION' THEN IndexSizeGB END DESC,
        CASE WHEN @Action = 'REORGANIZE_PARTITION' THEN EndTime END DESC;

    SELECT @RunningRows = ISNULL(@RunningRows,N'') +
        N'<tr><td>' + DatabaseName + N'</td>' +
        N'<td>' + IndexName + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(IndexSizeGB,'N2') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(BeforeFragmentationPercent,'N2') + N'%</td>' +
        N'<td>' + ISNULL(ExecutedAction,N'') + N'</td>' +
        N'<td>' + Status + N'</td>' +
        N'<td>' + CONVERT(nvarchar(30), StartTime, 120) + N'</td>' +
        N'<td style="text-align:right;">' + CAST(DATEDIFF(MINUTE, StartTime, SYSDATETIME()) AS nvarchar(20)) + N'</td></tr>'
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status = 'RUNNING';

    SELECT TOP (30) @QueuedRows = ISNULL(@QueuedRows,N'') +
        N'<tr><td>' + DatabaseName + N'</td>' +
        N'<td>' + IndexName + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(IndexSizeGB,'N2') + N'</td>' +
        N'<td style="text-align:right;">' + FORMAT(BeforeFragmentationPercent,'N2') + N'%</td>' +
        N'<td>' + Status + N'</td></tr>'
    FROM dbo.LargeDB_IndexMaintenanceWorkQueue
    WHERE RecommendedAction = @Action
      AND Status IN ('QUEUED','STOPPED','FAILED')
    ORDER BY
        CASE WHEN @Action = 'REORGANIZE_PARTITION' THEN IndexSizeGB END ASC,
        CASE WHEN @Action = 'REBUILD_PARTITION' THEN IndexSizeGB END DESC;

    SET @Body = N'
<html>
<head>
<style>
body { font-family: Segoe UI, Arial, sans-serif; font-size:13px; color:#222; }
h1 { color:#17365D; font-size:22px; }
h2 { color:#003366; font-size:18px; margin-top:24px; }
table { border-collapse:collapse; width:100%; margin-top:10px; }
th { background:#e9eef5; border:1px solid #cfd8e3; padding:7px; text-align:left; }
td { border:1px solid #d9e2ec; padding:7px; }
.box { padding:12px; border:1px solid #d6d6d6; background:#f8f9fb; margin:12px 0; }
.footer { border-top:3px solid #2f5597; margin-top:30px; padding-top:10px; font-size:12px; color:#555; }
</style>
</head>
<body>

<h1>' + @Title + N'</h1>

<div class="box">
<b>Report Created:</b> ' + CONVERT(nvarchar(30), @Now, 120) + N'<br/>
<b>Maintenance Type:</b> ' + UPPER(@MaintenanceType) + N'<br/>
<b>Last Good Run Date:</b> ' + ISNULL(CONVERT(nvarchar(30), @LastGoodRunDate, 120), N'No successful run found') + N'<br/>
<b>Last Good RunID:</b> ' + ISNULL(CONVERT(nvarchar(50), @LastGoodRunID), N'N/A') + N'<br/>
<b>Completed Items In Last Good Run:</b> ' + FORMAT(ISNULL(@CompletedCount,0),'N0') + N'<br/>
<b>Total Processed In Last Good Run:</b> ' + FORMAT(ISNULL(@ProcessedGB,0),'N2') + N' GB / ' + FORMAT(ISNULL(@ProcessedTB,0),'N2') + N' TB<br/>
<b>Total Duration In Last Good Run:</b> ' + FORMAT(ISNULL(@TotalDurationMinutes,0),'N0') + N' minutes / ' + FORMAT(ISNULL(@TotalDurationHours,0),'N2') + N' hours<br/>
<b>Average Minutes Per GB:</b> ' + FORMAT(ISNULL(@AvgMinutesPerGB,0),'N2') + N'<br/>
<b>Remaining Eligible Work:</b> ' + FORMAT(ISNULL(@RemainingGB,0),'N2') + N' GB / ' + FORMAT(ISNULL(@RemainingTB,0),'N2') + N' TB
</div>

<h2>Status Summary</h2>
<table>
<tr><th>Status</th><th>Item Count</th><th>Total GB</th><th>Total TB</th></tr>'
+ CASE WHEN NULLIF(@SummaryRows,N'') IS NULL
       THEN N'<tr><td colspan="4" style="text-align:center;font-weight:bold;color:#666;">No Records Found</td></tr>'
       ELSE @SummaryRows END + N'
</table>

<h2>Latest Successful Operations From Last Good Run</h2>
<table>
<tr><th>Database</th><th>Index</th><th>Size GB</th><th>Before Frag</th><th>Executed Action</th><th>Status</th><th>Start Time</th><th>End Time</th><th>Duration Min</th><th>Duration Hours</th><th>Min / GB</th></tr>'
+ CASE WHEN NULLIF(@CompletedRows,N'') IS NULL
       THEN N'<tr><td colspan="11" style="text-align:center;font-weight:bold;color:#666;">No Records Found</td></tr>'
       ELSE @CompletedRows END + N'
</table>

<h2>Currently Running</h2>
<table>
<tr><th>Database</th><th>Index</th><th>Size GB</th><th>Before Frag</th><th>Executed Action</th><th>Status</th><th>Start Time</th><th>Running Min</th></tr>'
+ CASE WHEN NULLIF(@RunningRows,N'') IS NULL
       THEN N'<tr><td colspan="8" style="text-align:center;font-weight:bold;color:#666;">No Records Found</td></tr>'
       ELSE @RunningRows END + N'
</table>

<h2>Next Items In Queue</h2>
<table>
<tr><th>Database</th><th>Index</th><th>Size GB</th><th>Before Frag</th><th>Status</th></tr>'
+ CASE WHEN NULLIF(@QueuedRows,N'') IS NULL
       THEN N'<tr><td colspan="5" style="text-align:center;font-weight:bold;color:#666;">No Records Found</td></tr>'
       ELSE @QueuedRows END + N'
</table>

<div class="footer">
<b>End of Report</b><br/>
' + @Title + N'<br/>
Server: ' + @ServerName + N'<br/>
Generated On: ' + CONVERT(nvarchar(30), @Now, 120) + N'<br/><br/>
This is an automated message from the DBA Observability Framework.
</div>

</body>
</html>';

    EXEC msdb.dbo.sp_send_dbmail
          @profile_name = @ProfileName
        , @recipients = @Recipients
        , @subject = @Subject
        , @body = @Body
        , @body_format = 'HTML';
END;

