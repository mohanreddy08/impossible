# ASHA — Frontline Health-Worker Companion

Offline-first companion for ASHA/ANM frontline health workers (Telugu and English). **Prototype on SYNTHETIC data. Not clinically validated, not medical advice, not ready for real patients.**

| Folder | What it is |
|---|---|
| `health-worker-app/` | Flutter app (Android; iOS not built or tested). See its `README.md`. |
| `health-worker-backend/` | FastAPI server for sync, reports and protocol retrieval. See its `README.md`. |
| `health-worker-datasets/` | Synthetic test datasets (no real patients, no real protocols). |
| `PROJECT_AUDIT_REPORT.md` | Honest status audit: what works, what is untested, what is missing. |

No secrets are stored in this repository. Server keys are supplied through environment variables (see the backend README); create your own `.env` locally and never commit it.
