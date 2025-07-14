-- function: keep_provision_status()
-- description: keep the status_id the same when called before update
CREATE OR REPLACE FUNCTION keep_provision_status_and_increment_attempt_count() RETURNS TRIGGER AS $$
BEGIN
    NEW.attempt_count := NEW.attempt_count + 1;
    NEW.status_id := OLD.status_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;