# MBQC Verification in Maude

This repository contains the Maude implementation and evaluation artifacts for a verification workflow for measurement-based quantum computation (MBQC).

The workflow compiles circuit descriptions into MBQC patterns, applies standardization and signal shifting, performs structural checks, and verifies the resulting computation using a guarded representative-branch execution.

## Scope

The implementation targets circuit-derived MBQC patterns generated from circuits over the supported `J(alpha)` and `CZ` gates.

The verification workflow is intended for the accepted pattern fragment checked by the implementation. It is not intended as a general verifier for arbitrary raw MBQC patterns.

The current implementation compares pure quantum states using squared fidelity.

## Requirements

The artifact was evaluated with:

- Maude 3.5
- Bash
- Python 3
- GNU `timeout`
- GNU `time`

## Quick Check

From the repository root, run:

```bash
./run_checks.sh
```
This executes the selected regression tests together with the RQ1 and RQ2 evaluations and an RQ3 smoke test.

A successful run ends with:
```
ALL CHECKS PASSED
```
Generated check logs are stored under:
```
artifacts/checks/
```
## Evaluation Files
### RQ1

Evaluation input:
```
evaluation/eval_rq1_integrated.maude
```
Saved final result:
```
results/rq1_final.txt
```
### RQ2
Evaluation input:
```
evaluation/eval_rq2_integrated.maude
```
Saved final result:
```
results/rq2_final.txt
```
### RQ3

RQ3 uses the following experiment drivers:
```
run_rq3_once.sh
run_rq3_experiment.sh
reproduce_rq3_paper.sh
```
The common RQ3 definitions are located under:
```
evaluation/common/
```
## Full and Proposed Methods
For RQ3, the two reported verification methods are:
- Full: full-branch execution followed by the fidelity check.
- Proposed: structural checks followed by representative-branch execution and the fidelity check.

Both methods operate on the transformed pattern used in the post-transformation verification experiment.

## Reproducing the RQ3 Experiment

The paper configuration can be launched with:
```
./reproduce_rq3_paper.sh
```
This runs five repetitions for the workloads used in the paper, including GHZ6.

Note: the complete RQ3 experiment is computationally expensive and can require substantial execution time and memory. Running ./run_checks.sh is recommended for a quick validation of the artifact.

## Saved Final Results

The saved final RQ3 dataset is located at:

results/rq3_final_postfreeze/

The main summary files are:
```
results/rq3_final_postfreeze/comparison.csv
results/rq3_final_postfreeze/summary.csv
results/rq3_final_postfreeze/runs.csv
results/rq3_final_postfreeze/manifest.txt
```
The directory also contains the raw run outputs, per-run records, and timing records used to construct the final summaries.
