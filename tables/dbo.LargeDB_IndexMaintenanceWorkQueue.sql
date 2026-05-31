/****** Object:  Table [dbo].[LargeDB_IndexMaintenanceWorkQueue]    Script Date: 5/31/2026 12:23:25 PM ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[LargeDB_IndexMaintenanceWorkQueue](
	[WorkQueueID] [bigint] IDENTITY(1,1) NOT NULL,
	[RunID] [uniqueidentifier] NOT NULL,
	[QueueCreateTime] [datetime2](0) NOT NULL,
	[StartTime] [datetime2](0) NULL,
	[EndTime] [datetime2](0) NULL,
	[ServerName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[DatabaseName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[SchemaName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[TableName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IndexName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IndexID] [int] NOT NULL,
	[PartitionNumber] [int] NOT NULL,
	[PageCount] [bigint] NULL,
	[IndexSizeGB] [decimal](18, 2) NULL,
	[BeforeFragmentationPercent] [decimal](9, 2) NULL,
	[AfterFragmentationPercent] [decimal](9, 2) NULL,
	[RecommendedAction] [varchar](40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ExecutedAction] [varchar](40) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Status] [varchar](30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AttemptCount] [int] NOT NULL,
	[CommandText] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Message] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ErrorNumber] [int] NULL,
	[ErrorMessage] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
PRIMARY KEY CLUSTERED 
(
	[WorkQueueID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

ALTER TABLE [dbo].[LargeDB_IndexMaintenanceWorkQueue] ADD  DEFAULT (sysdatetime()) FOR [QueueCreateTime]
ALTER TABLE [dbo].[LargeDB_IndexMaintenanceWorkQueue] ADD  DEFAULT (@@servername) FOR [ServerName]
ALTER TABLE [dbo].[LargeDB_IndexMaintenanceWorkQueue] ADD  DEFAULT ('QUEUED') FOR [Status]
ALTER TABLE [dbo].[LargeDB_IndexMaintenanceWorkQueue] ADD  DEFAULT ((0)) FOR [AttemptCount]
