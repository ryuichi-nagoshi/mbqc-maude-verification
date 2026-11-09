# MBQC Verification in Maude

This repository contains the Maude implementation and evaluation artifacts for:

**Efficient Formal Verification of Measurement-Based Quantum Computation by Branch Reduction Based on Structural Checking**  
Ryuichi Nagoshi and Tsubasa Takagi, SFPVV 2026 (accepted; proceedings forthcoming).

Publication details and DOI will be added after publication.

**Reproducible release:** [SFPVV2026 Artifact v1.0](https://github.com/ryuichi-nagoshi/mbqc-maude-verification/releases/tag/sfpvv2026-artifact-v1.0)

## Scope

The implementation verifies circuit-derived MBQC patterns generated using the supported `J(alpha)` and `CZG` constructors. It is not a general verifier for arbitrary MBQC patterns.

## Requirements

- Maude 3.5
- Bash and Python 3
- GNU `timeout` and `time`
- Git

## Quick Check

Run from the repository root:

```bash
./run_checks.sh
```

This runs regression checks, RQ1/RQ2 evaluations, and an RQ3 smoke test. A successful run ends with `ALL CHECKS PASSED`.

## Evaluation and Reproduction

- **RQ1:** `evaluation/eval_rq1_integrated.maude`  
  Results: `results/rq1_final.txt`
- **RQ2:** `evaluation/eval_rq2_integrated.maude`  
  Results: `results/rq2_final_postaudit.txt`
- **RQ3:** `./reproduce_rq3_paper.sh`  
  Results: `results/rq3_final_postfreeze/`
- **RQ3 diagnostics:** `results/rq3_cost_breakdown_current/`

The RQ3 reproduction script performs five repetitions of the Full and Proposed methods. It explicitly sets `--timeout 3600`. The generic driver's default is 900 seconds, which is insufficient for GHZ6. Full reproduction may require substantial time and memory.

## RQ3 Provenance

The saved manifests contain source hashes and internal laboratory Git revision identifiers. The source hashes match the frozen artifact release; the internal revision identifiers are not part of this GitHub repository's history. The five-run results and one-run diagnostics were collected in separate sessions.
