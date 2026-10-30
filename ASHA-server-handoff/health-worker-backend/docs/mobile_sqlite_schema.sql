-- Planned on-device (Flutter/sqflite) schema. Mirrors the server models so the same business concepts apply offline.
-- Differences from the server: no audit_log/reports table (reports are generated locally), plus an outbox for sync.
PRAGMA foreign_keys = ON;

CREATE TABLE households (
  household_id TEXT PRIMARY KEY, village_id TEXT NOT NULL, assigned_worker_id TEXT NOT NULL,
  household_member_count INTEGER NOT NULL CHECK (household_member_count >= 1),
  eligible_followup_categories TEXT NOT NULL,            -- "|ANC|ROUTINE|"
  last_visit_date TEXT, next_visit_due_date TEXT, scheduled_followup_category TEXT,
  record_status TEXT NOT NULL CHECK (record_status IN ('UPCOMING','DUE_TODAY','OVERDUE','COMPLETED','NO_VISIT_DUE')),
  last_updated TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,   -- version = last server version seen (base_version for updates)
  synthetic_record INTEGER NOT NULL DEFAULT 1, dirty INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX ix_hh_due ON households(next_visit_due_date);

CREATE TABLE visits (
  visit_id TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(household_id), worker_id TEXT NOT NULL,
  scheduled_date TEXT NOT NULL, actual_visit_date TEXT, actual_visit_time TEXT,
  visit_status TEXT NOT NULL CHECK (visit_status IN ('PLANNED','COMPLETED','MISSED','RESCHEDULED','CANCELLED')),
  visit_reason TEXT NOT NULL, followup_required INTEGER, next_followup_date TEXT,
  referral_status TEXT NOT NULL DEFAULT 'NONE' CHECK (referral_status IN ('NONE','RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')),
  referral_id TEXT, recorded_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
  synthetic_record INTEGER NOT NULL DEFAULT 1, dirty INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX ix_visits_status_sched ON visits(visit_status, scheduled_date);

CREATE TABLE facilities (facility_id TEXT PRIMARY KEY);
CREATE TABLE referrals (
  referral_id TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(household_id), visit_id TEXT NOT NULL REFERENCES visits(visit_id),
  facility_id TEXT NOT NULL REFERENCES facilities(facility_id), service_category TEXT NOT NULL,
  referral_created_date TEXT NOT NULL, planned_visit_date TEXT,
  referral_status TEXT NOT NULL CHECK (referral_status IN ('RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')),
  attendance_confirmed INTEGER NOT NULL DEFAULT 0, attendance_confirmation_date TEXT, attendance_record_id TEXT,
  record_state TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (record_state IN ('ACTIVE','CANCELLED','INVALID','DUPLICATE')),
  duplicate_of TEXT, last_updated TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, synthetic_record INTEGER NOT NULL DEFAULT 1,
  dirty INTEGER NOT NULL DEFAULT 0,
  CHECK (attendance_confirmed = (referral_status = 'ATTENDANCE_CONFIRMED'))
);

-- Protocol content shipped with the app (read-only on device)
CREATE TABLE protocol_documents (document_id TEXT PRIMARY KEY, title TEXT, issuing_authority TEXT, version TEXT, publication_date TEXT,
  language TEXT, source_verification_status TEXT NOT NULL, approved_for_retrieval INTEGER NOT NULL);
CREATE TABLE protocol_passages (passage_id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES protocol_documents(document_id),
  section_id TEXT, section_title TEXT, page_number INTEGER, passage_text TEXT NOT NULL, language TEXT,
  approved_for_retrieval INTEGER NOT NULL, source_verification_status TEXT NOT NULL);
-- Same construction as the Python ProtocolIndex: tokens are normalised (NFC, casefold, ZWJ/ZWNJ stripped, split on non-letters)
-- BEFORE insert, and the 'ascii' tokenizer keeps Telugu code points intact.
CREATE VIRTUAL TABLE passages_fts USING fts5(pid UNINDEXED, tokens, tokenize='ascii');

-- Offline write queue: one row per local change, uploaded via POST /sync/push; delete only after the server acknowledges it
CREATE TABLE sync_outbox (
  op_id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
  op_type TEXT NOT NULL CHECK (op_type IN ('create','update')), base_version INTEGER, payload TEXT NOT NULL,
  client_created_at TEXT NOT NULL, client_updated_at TEXT,
  state TEXT NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','ACKNOWLEDGED','REJECTED','CONFLICT')),
  last_error_code TEXT, conflict_json TEXT, attempts INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE sync_state (installation_id TEXT PRIMARY KEY, last_pull_server_time TEXT, last_ack_at TEXT);
-- Locally generated reports (so reports never depend on the server)
CREATE TABLE local_reports (report_id TEXT PRIMARY KEY, facility_id TEXT, period_start TEXT, period_end TEXT, generated_at TEXT,
  data_as_of TEXT, last_sync_at TEXT, content_hash TEXT, payload_json TEXT);
