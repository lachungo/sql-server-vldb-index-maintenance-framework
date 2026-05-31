# Architecture

## Overview

The SQL Server VLDB Index Maintenance Framework is a queue-based maintenance orchestration platform designed for multi-terabyte SQL Server environments.

## Design Goals

- Controlled maintenance execution
- Resumable maintenance windows
- Availability Group awareness
- Progress tracking and reporting
- Transaction log protection
- Operational visibility

## Workflow

```text
Fragmentation Capture
        ↓
Candidate Selection
        ↓
Work Queue Generation
        ↓
REORG / REBUILD Orchestration
        ↓
Progress Tracking
        ↓
Log Backup Assistance
        ↓
Drive Space Monitoring
        ↓
Operational Reporting
```

## Core Components

- Queue Builder
- Maintenance Orchestrator
- Progress Tracking
- Reporting Engine
- Drive Space Monitoring
- Log Backup Assistance

## Operational Characteristics

- Queue-based execution
- Window-aware processing
- AG-aware safeguards
- Resumable operations
- Auditable progress tracking
