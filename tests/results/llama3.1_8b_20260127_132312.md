# Test Results: llama3.1:8b

**Date:** 2026-01-27 13:23:12  
**Model:** llama3.1:8b  
**Host:** plebdesk  

---

| Test | Result | Time | Iterations | Notes |
|------|--------|------|------------|-------|
| test1_python | PASS | 3s | 2 |  |
| test2_config | PASS | 4s | 2 |  |
| test3_shell | FAIL | 8s | 2 | Verification failed |
| test4_transform | FAIL | 6s | 2 | Verification failed |
| test5_errors | PASS | 4s | 2 |  |
| test6_multifile | FAIL | 6s | 2 | Verification failed |
| test7_debug | FAIL | 10s | 2 | Verification failed |
| test8_format | FAIL | 2s | 2 | Verification failed |

---

## Summary

- **Passed:** 3/8
- **Total Time:** 43s
- **Average:** 5s per test
- **Total Iterations:** 16
- **Avg Iterations:** 2.0 per test
- **Quality Score:** 62/100

### Score Breakdown

| Dimension | Weight | Description |
|-----------|--------|-------------|
| Correctness | 40% | Tests passed |
| Efficiency | 20% | Fewer iterations is better (baseline: 3/test) |
| Speed | 20% | Faster is better (baseline: 15s/test) |
| Format | 20% | Output correctness |

## Test Artifacts

Saved to: `/home/plebdesk/Desktop/local-sub-agents/tests/results/`
