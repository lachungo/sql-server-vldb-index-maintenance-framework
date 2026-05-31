# SQL Server VLDB Index Maintenance Framework

## Enterprise Queue-Based Index Maintenance for Multi-Terabyte SQL Server Environments

### Features
- Queue-driven maintenance execution
- AG-aware orchestration
- Resumable maintenance windows
- Fragmentation baselining
- Progress tracking and reporting
- Drive space protection
- Transaction log growth management

## Repository Structure

```text
agent-jobs/
stored-procedures/
tables/
docs/
```

## Documentation

The docs folder contains:

- Operations Runbook
- Queue Reset Procedures
- REORG and REBUILD Workflows
- Azure Backup Investigation Guidance
- Log Growth Remediation Procedures
- Disaster Recovery Guidance

## Design Goals

Built for very large SQL Server databases where traditional maintenance approaches become difficult due to maintenance windows, transaction log growth, and high availability requirements.

## Author

Louis Achungo
Principal SQL Architect | Cloud Database DBS (Azure | AWS)
