-- Purpose: Remove NOT NULL constraint from metadata column in all tables that have metadata column.

-- Update metadata column in subscription table
BEGIN;
ALTER TABLE public.subscription ALTER COLUMN metadata DROP NOT NULL;
COMMIT;
