/****** Object:  Table [dbo].[LargeDB_MaintenanceProgress]    Script Date: 5/31/2026 12:23:25 PM ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[LargeDB_MaintenanceProgress](
	[ProgressID] [bigint] IDENTITY(1,1) NOT NULL,
	[StartTime] [datetime2](0) NOT NULL,
	[EndTime] [datetime2](0) NULL,
	[ServerName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[DatabaseName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[SchemaName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TableName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IndexName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PartitionNumber] [int] NULL,
	[OperationType] [varchar](60) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IndexSizeGB] [decimal](18, 2) NULL,
	[FragmentationPercent] [decimal](9, 2) NULL,
	[Status] [varchar](30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[CommandText] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Message] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ErrorNumber] [int] NULL,
	[ErrorMessage] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
PRIMARY KEY CLUSTERED 
(
	[ProgressID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

ALTER TABLE [dbo].[LargeDB_MaintenanceProgress] ADD  DEFAULT (sysdatetime()) FOR [StartTime]
ALTER TABLE [dbo].[LargeDB_MaintenanceProgress] ADD  DEFAULT (@@servername) FOR [ServerName]
ALTER TABLE [dbo].[LargeDB_MaintenanceProgress] ADD  DEFAULT ('STARTED') FOR [Status]
