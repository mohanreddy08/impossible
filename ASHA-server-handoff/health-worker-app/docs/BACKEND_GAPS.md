# Backend gaps found while building the app (documented, not worked around silently)
1. **No facility directory endpoint** - the facility picker is derived from referrals already on the phone.
2. **No visit notes field** - the brief asked for notes "where supported"; they are not supported, so not offered.
3. **No login/token endpoint** - only static `X-API-Key`. "Expired credentials" is handled as 401 -> Settings banner.
4. **Pull cursor is a 1-second timestamp with a strict `>` filter** and no tie-breaker. The app compensates with a 1-second overlap (found by the real-backend test).
   More than 500 changes sharing one second cannot be paged correctly: add a keyset cursor (timestamp + id) server-side.
5. **`GET /protocols/{id}/passages` returns passages of any verification status**; the app filters to VERIFIED+approved itself. Prefer a server-side `approved_only` filter.
6. **Server stores no field-level history** for stale merges beyond the conflict log; the app shows what the API returns.
7. Backend safety engine quirk (unchanged here): phrase cues such as "now" are matched as substrings. The Dart port reproduces it exactly so both agree; fix in both together.
8. Report endpoint `data_freshness_label` depends on `last_sync_at` supplied by the client; the app sends its own last successful sync time.
9. **No visit time-of-day field.** `visits` stores `actual_visit_date` (a date) and a server-set `recorded_at`; `VisitCreate/VisitUpdate` reject unknown fields (`extra="forbid"`). The app records the time a worker went on a visit on the phone only (schema v3 `visit_times`). To share it: add `actual_visit_time` (nullable) to the model, an Alembic migration, the schemas, sync apply/pull, tests and the OpenAPI/contract, then send it in the sync payload.
