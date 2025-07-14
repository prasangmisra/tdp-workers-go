DROP TRIGGER IF EXISTS provision_hosting_certificate_create_failure_tg ON provision_hosting_certificate_create;
DROP TRIGGER IF EXISTS provision_hosting_create_failure_tg ON provision_hosting_create;

-- function: mark_hosting_record_failed
-- description: marks a hosting record as failed and sets is_deleted to true
CREATE OR REPLACE FUNCTION mark_hosting_record_failed() RETURNS TRIGGER AS $$
BEGIN

    UPDATE ONLY hosting
    SET status = 'Failed',
        is_deleted = TRUE
    WHERE id = NEW.hosting_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql; 

-- Trigger to remove hosting record if we failed certificate creation
CREATE TRIGGER provision_hosting_certificate_create_failure_tg
    AFTER UPDATE ON provision_hosting_certificate_create
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('provision_status', 'failed')
    ) EXECUTE PROCEDURE mark_hosting_record_failed();

-- Trigger to delete a hosting record if sending the hosting request to SAAS fails
CREATE TRIGGER provision_hosting_create_failure_tg
    AFTER UPDATE ON provision_hosting_create
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('provision_status', 'failed')
    ) EXECUTE PROCEDURE mark_hosting_record_failed();