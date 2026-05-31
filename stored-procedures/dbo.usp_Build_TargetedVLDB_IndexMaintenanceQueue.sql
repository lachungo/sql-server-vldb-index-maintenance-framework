SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

/*==============================================================================
  Procedure: dbo.usp_Build_TargetedVLDB_IndexMaintenanceQueue

  Purpose:
      Builds the VLDB index maintenance execution queue from the latest
      targeted fragmentation capture snapshot.

  Architecture Role:
      This procedure is the PLANNING ENGINE of the VLDB maintenance framework.
      It does NOT execute index maintenance operations.

      Responsibilities include:
          - Reading latest fragmentation capture telemetry
          - Determining eligible maintenance candidates
          - Deciding REBUILD vs REORGANIZE actions
          - Applying fragmentation and size thresholds
          - Generating execution queue entries
          - Assigning a unified RunID for orchestration tracking

  Execution Flow:
      1. dbo.usp_Capture_TargetedFragmentation
      2. dbo.usp_Build_TargetedVLDB_IndexMaintenanceQueue
      3. dbo.usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto

  Queue Output Table:
      dbo.LargeDB_IndexMaintenanceWorkQueue

  Queue Consumption:
      dbo.usp_Run_TargetedVLDB_IndexMaintenanceQueue_Auto

  Design Notes:
      - REBUILD candidates are typically processed largest-first
      - REORGANIZE candidates are typically processed smallest-first
      - Queue persistence allows stop/restart resiliency
      - Queue survives maintenance windows and SQL Agent restarts
      - RunID enables reporting and historical auditing

  Typical Schedule:
      Thursday evening after fragmentation capture completes.

==============================================================================*/

CREATE PROCEDURE [dbo].[usp_Build_TargetedVLDB_IndexMaintenanceQueue]
      @RunID uniqueidentifier = NULL OUTPUT
    , @MinRebuildFragmentationPercent decimal(9,2) = 30
    , @MinReorgFragmentationPercent decimal(9,2) = 5
    , @MinIndexSizeGB decimal(18,2) = 10
    , @IncludeReorg bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- Generate new RunID when not supplied
    -------------------------------------------------------------------------
    IF @RunID IS NULL
        SET @RunID = NEWID();

    -------------------------------------------------------------------------
    -- Build latest capture snapshot reference
    -------------------------------------------------------------------------
    ;WITH LatestCapture AS
    (
        SELECT
              DatabaseName
            , SchemaName
            , TableName
            , MAX(CaptureTime) AS CaptureTime
        FROM dbo.LargeDB_TargetedFragmentation
        GROUP BY
              DatabaseName
            , SchemaName
            , TableName
    )

    -------------------------------------------------------------------------
    -- Insert eligible maintenance candidates into work queue
    -------------------------------------------------------------------------
    INSERT INTO dbo.LargeDB_IndexMaintenanceWorkQueue
    (
        RunID,
        DatabaseName,
        SchemaName,
        TableName,
        IndexName,
        IndexID,
        PartitionNumber,
        PageCount,
        IndexSizeGB,
        BeforeFragmentationPercent,
        RecommendedAction,
        Status,
        Message
    )
    SELECT
          @RunID
        , f.DatabaseName
        , f.SchemaName
        , f.TableName
        , f.IndexName
        , f.IndexID
        , f.PartitionNumber
        , f.PageCount
        , f.IndexSizeGB
        , f.FragmentationPercent
        , f.RecommendedAction
        , 'QUEUED'
        , 'Queued from latest targeted fragmentation capture.'
    FROM dbo.LargeDB_TargetedFragmentation f
    JOIN LatestCapture lc
        ON  f.DatabaseName = lc.DatabaseName
        AND f.SchemaName   = lc.SchemaName
        AND f.TableName    = lc.TableName
        AND f.CaptureTime  = lc.CaptureTime
    WHERE
            f.IndexSizeGB >= @MinIndexSizeGB
        AND
        (
                f.FragmentationPercent >= @MinRebuildFragmentationPercent

             OR

             (
                    @IncludeReorg = 1
                AND f.FragmentationPercent >= @MinReorgFragmentationPercent
                AND f.FragmentationPercent <  @MinRebuildFragmentationPercent
             )
        )
        AND f.RecommendedAction IN
        (
            'REBUILD_PARTITION',
            'REORGANIZE_PARTITION'
        );

    -------------------------------------------------------------------------
    -- Return generated RunID
    -------------------------------------------------------------------------
    SELECT @RunID AS RunID;

END;

