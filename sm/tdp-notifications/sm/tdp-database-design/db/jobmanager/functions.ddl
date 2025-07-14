-- function: job_start_date
-- description: This function calculates the start date for a job based on the attempt count.
CREATE OR REPLACE FUNCTION job_start_date(attempt_count INT) RETURNS TIMESTAMPTZ AS $$
DECLARE
  _factor INT;
  _start_date TIMESTAMPTZ;
BEGIN
  -- Get the default factor for exponential backoff
  SELECT default_value INTO _factor FROM attr_key WHERE name = 'provision_retry_backoff_factor';

  -- Calculate the start date for the job based on the attempt count (exponential backoff).
  _start_date := CASE
    WHEN attempt_count = 1 THEN NOW()
    ELSE NOW() + INTERVAL '1 second' * (_factor ^ (attempt_count - 1))
  END;

  RETURN _start_date;
END;
$$ LANGUAGE plpgsql;
