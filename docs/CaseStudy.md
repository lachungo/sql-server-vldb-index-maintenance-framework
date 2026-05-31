# Case Study: Establishing a Fragmentation Baseline in a Multi‑Terabyte SQL Server Environment

## Challenge

Traditional blanket index maintenance approaches become difficult to manage at VLDB scale due to:

- Limited maintenance windows
- Large index sizes
- Transaction log growth
- High availability requirements
- Backup coordination challenges

## Approach

A custom queue-based framework was developed to:

1. Capture fragmentation
2. Select candidates
3. Build a persistent work queue
4. Execute REORG and REBUILD operations in controlled windows
5. Track progress and support recovery

## Results

- Initial fragmentation baseline successfully established
- Hundreds of candidate indexes evaluated
- Queue-based orchestration validated
- Maintenance resumption validated
- Operational reporting automated
- REORG maintenance proven effective for ongoing maintenance

## Key Findings

### What Worked Well

- Queue-based execution
- Progress tracking
- AG-aware execution
- Maintenance window enforcement
- Recovery and restart capability

### Areas for Further Investigation

Large-scale REBUILD activity revealed backup coordination considerations that warrant further review:

- Backup architecture alignment
- Snapshot/VSS approaches
- Schedule coordination
- Transaction log management

## Lessons Learned

- Establishing a baseline is critical
- REORG operations can maintain index health effectively
- Operational visibility is essential
- Backup and maintenance strategies must be designed together
- Resumable maintenance significantly reduces operational risk
