
DROP INDEX IF EXISTS job_status_is_final_is_success_is_cond_idx;

ALTER TABLE job_status DROP COLUMN IF EXISTS is_cond;
ALTER TABLE provision_status DROP COLUMN IF EXISTS is_cond;

CREATE TABLE IF NOT EXISTS job_reference_status_override (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  status_id               UUID NOT NULL REFERENCES job_status,
  reference_status_table  TEXT NOT NULL,
  reference_status_id     UUID NOT NULL,
  UNIQUE(status_id, reference_status_table, reference_status_id)
);

-- Job reference status overrides per reference table
INSERT INTO job_reference_status_override(status_id, reference_status_table, reference_status_id) VALUES
(tc_id_from_name('job_status','completed_conditionally'), 'provision_status', tc_id_from_name('provision_status','pending_action'));

CREATE OR REPLACE FUNCTION job_reference_status_update() RETURNS TRIGGER AS $$
DECLARE
_job_type               RECORD;
_job_status             RECORD;
_target_status          RECORD;
BEGIN

  SELECT * INTO _job_type FROM job_type WHERE id = NEW.type_id;

  IF _job_type.reference_table IS NULL THEN 
    RETURN NEW;
  END IF;

  SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

  IF NOT _job_status.is_final THEN 
    RETURN NEW;
  END IF;

  -- first check if there are reference specific overrides
  EXECUTE FORMAT(
    'SELECT rst.* FROM %s rst JOIN job_reference_status_override jrso ON jrso.reference_status_id = rst.id WHERE jrso.status_id = $1',
    _job_type.reference_status_table
  )
    INTO _target_status
    USING _job_status.id;

  IF _target_status.id IS NULL THEN
    EXECUTE FORMAT('SELECT * FROM %s WHERE is_final AND is_success = $1',_job_type.reference_status_table)
      INTO _target_status
      USING _job_status.is_success;

    IF _target_status.id IS NULL THEN 
      RAISE EXCEPTION 'no target status found in table % where is_success=%',
        _job_type.reference_status_table,_job_status.is_success;
    END IF;

  END IF;

  EXECUTE FORMAT('UPDATE "%s" SET %s = $1 WHERE id = $2',
    _job_type.reference_table,
    _job_type.reference_status_column
  )
  USING _target_status.id,NEW.reference_id;
   
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

