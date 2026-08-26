BEGIN TRANSACTION;
CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'quarantine',
  content TEXT NOT NULL,
  modules TEXT NOT NULL,
  bound_paths TEXT NOT NULL,
  evidence TEXT NOT NULL,
  created_at TEXT NOT NULL,
  reviewed_by TEXT,
  reviewed_at TEXT
);
INSERT INTO "memories" VALUES('mem-20260826065545340679','review_finding','quarantine','New C helpers must not strcpy an unconstrained parameter into a fixed stack buffer (common/cli.c:361) — use snprintf/strlcpy with the destination size and skip the scratch copy.','["common/**"]','["common/cli.c"]','{"review_artifact": "7e7b6ad4"}','2026-08-26T06:55:45+00:00',NULL,NULL);
INSERT INTO "memories" VALUES('mem-20260826065545384003','review_finding','active','Every malloc result in common/ must be NULL-checked before use (common/cli.c:362 passes the pointer straight to snprintf), matching the run_command_list() precedent at common/cli.c:141-143.','["common/**"]','["common/cli.c"]','{"review_artifact": "7e7b6ad4"}','2026-08-26T06:55:45+00:00','human-mde','2026-08-26T06:55:45+00:00');
COMMIT;
