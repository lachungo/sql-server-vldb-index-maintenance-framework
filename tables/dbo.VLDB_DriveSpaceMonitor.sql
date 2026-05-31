/****** Object:  Table [dbo].[VLDB_DriveSpaceMonitor]    Script Date: 5/31/2026 12:23:26 PM ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[VLDB_DriveSpaceMonitor](
	[MonitorID] [bigint] IDENTITY(1,1) NOT NULL,
	[CaptureTime] [datetime2](0) NOT NULL,
	[DriveLetter] [varchar](10) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[VolumeName] [sysname] COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TotalGB] [decimal](18, 2) NULL,
	[FreeGB] [decimal](18, 2) NULL,
	[FreePct] [decimal](10, 2) NULL,
	[Status] [varchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
PRIMARY KEY CLUSTERED 
(
	[MonitorID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[VLDB_DriveSpaceMonitor] ADD  DEFAULT (sysdatetime()) FOR [CaptureTime]
