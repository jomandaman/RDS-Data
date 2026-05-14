# EYE Toolbox: Thesis Analysis Notebooks

Stereoscopic vision therapy games (Track B of EYE Toolbox). Master's thesis, CSS 595, University of Washington Bothell. Author: Josiah Zacharias. Defense: May 20, 2026.

## Contents

Each notebook is one evaluation pillar in the thesis.

- `pillar_a_security.ipynb`: Phase 0 hardening. Static code-pattern audit (commit eaf0956 vs HEAD) and 21 live probes against the dev EC2 instance.
- `pillar_b_rest_api.ipynb`: REST API performance. Paired-endpoint timing across five legacy/REST surfaces and an 8-step authenticated session simulation.
- `pillar_c_clinician_adoption.ipynb`: Clinical adoption signal. NVI prescription patterns pre/post the 2025-07-14 cutover and the activity-tracker pipeline.
- `pillar_d_therapeutic_efficacy.ipynb`: Therapeutic efficacy. Within-NVI before/after on the modernized RDS and a 5-week demo portal pilot (199 users, 207 sessions).

## Viewing

GitHub renders notebooks inline. Click any `.ipynb` above to view figures and tables in your browser, no setup required.

## Reproduction

Patient data is excluded from this repo. Raw extracts are pulled by `scripts/fetch_pillar_*.sh` (require DB credentials and EC2 access), cleaned by `scripts/clean_data.py`, and aggregated by `scripts/build_pillar_*.py`. The notebooks' output cells reflect the most recent successful run.
