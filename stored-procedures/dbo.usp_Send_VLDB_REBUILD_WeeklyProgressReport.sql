SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON


CREATE   PROCEDURE dbo.usp_Send_VLDB_REBUILD_WeeklyProgressReport
      @ProfileName sysname = N'VLDB_AppDB System'
    , @Recipients nvarchar(max)
    , @LookbackHours int = 168
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_Send_VLDB_MaintenanceProgressReport_Core
          @ProfileName = @ProfileName
        , @Recipients = @Recipients
        , @LookbackHours = @LookbackHours
        , @MaintenanceType = 'REBUILD';
END;

