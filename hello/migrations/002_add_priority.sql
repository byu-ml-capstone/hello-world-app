-- Migration 002 — add a `priority` column to notes.
--
-- Example of an additive migration you can add without touching
-- migration 001. Applied automatically the next time the app starts;
-- existing rows get the default (0) via the DDL default.
--
-- Why `IF NOT EXISTS` on the column: same reason as migration 001 —
-- makes the migration safe to re-run against a database that already
-- got this column some other way (e.g. from a hand-run ALTER during
-- an incident). The _migrations table prevents normal re-runs, but
-- belt-and-suspenders is cheap.

ALTER TABLE notes ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 0;
