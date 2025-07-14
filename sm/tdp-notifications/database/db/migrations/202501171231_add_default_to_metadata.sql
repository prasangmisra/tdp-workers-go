-- Purpose: Add default value '{}' to metadata column in all tables that have metadata column.

-- Update metadata column in subscription table
BEGIN;
UPDATE public.subscription SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.subscription 
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;
COMMIT;