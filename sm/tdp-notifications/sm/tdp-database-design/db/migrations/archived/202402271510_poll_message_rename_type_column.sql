-- rename type column to type_id in poll_message table
DO $$
BEGIN
    IF EXISTS(SELECT *
        FROM information_schema.columns
        WHERE table_name='poll_message' and column_name='type')
      THEN
    ALTER TABLE IF EXISTS public.poll_message
        RENAME COLUMN type TO type_id;
    -- drop old foreign key constraint, create new constraint
    ALTER TABLE IF EXISTS public.poll_message
        DROP CONSTRAINT IF EXISTS poll_message_type_fkey,
        ADD CONSTRAINT poll_message_type_id_fkey FOREIGN KEY (type_id) REFERENCES poll_message_type(id);
    END IF;
END $$;
