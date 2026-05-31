/****** Object:  Table [dbo].[LargeDB_TargetedFragmentation]    Script Date: 5/31/2026 12:23:26 PM ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[LargeDB_TargetedFragmentation](
	[FragID] [bigint] IDENTITY(1,1) NOT NULL,
	[CaptureTime] [datetime2](0) NOT NULL,
	[ServerName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[DatabaseName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[SchemaName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[TableName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IndexName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IndexID] [int] NOT NULL,
	[PartitionNumber] [int] NOT NULL,
	[PageCount] [bigint] NOT NULL,
	[IndexSizeGB] [decimal](18, 2) NOT NULL,
	[FragmentationPercent] [decimal](9, 2) NOT NULL,
	[RecommendedAction] [varchar](40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[FragID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[LargeDB_TargetedFragmentation] ADD  DEFAULT (sysdatetime()) FOR [CaptureTime]
ALTER TABLE [dbo].[LargeDB_TargetedFragmentation] ADD  DEFAULT (@@servername) FOR [ServerName]
