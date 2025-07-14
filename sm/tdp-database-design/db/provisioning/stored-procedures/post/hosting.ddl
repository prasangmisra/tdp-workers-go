-- function: provision_hosting_certificate_create_success
-- description: updates the hosting certificate
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_success() RETURNS TRIGGER AS $$
DECLARE
    v_certificate_id UUID;
BEGIN
    INSERT INTO hosting_certificate
    (body, chain, private_key, not_before, not_after)
    SELECT body, chain, private_key, not_before, not_after
    FROM provision_hosting_certificate_create
    WHERE id = NEW.id RETURNING id INTO v_certificate_id;

    -- update hosting record
    UPDATE ONLY hosting
    SET certificate_id = v_certificate_id
    WHERE id = NEW.hosting_id;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_create_success TODO: UPDATE
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_create_success() RETURNS TRIGGER AS $$
BEGIN


    WITH hosting_update AS (
        UPDATE ONLY hosting
            SET
                -- do we need this? it looks like the worker is going
                -- to update the hosting object
                hosting_status_id = NEW.hosting_status_id,
                is_active = NEW.is_active,
                is_deleted = NEW.is_deleted,
                external_order_id = NEW.external_order_id
            WHERE id = NEW.hosting_id
            RETURNING client_id
    )
    UPDATE ONLY hosting_client
    SET
        external_client_id = NEW.external_client_id,
        username = NEW.client_username
    WHERE id = (SELECT client_id FROM hosting_update) AND external_client_id IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_update_success
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_update_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting h
    SET
        hosting_status_id = COALESCE(NEW.hosting_status_id, h.hosting_status_id),
        is_active = COALESCE(NEW.is_active, h.is_active),
        certificate_id = COALESCE(NEW.certificate_id, h.certificate_id)
    WHERE h.id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_delete_success
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_delete_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting h
    SET
        hosting_status_id = COALESCE(NEW.hosting_status_id, h.hosting_status_id),
        is_deleted = COALESCE(NEW.is_deleted, h.is_deleted),
        is_active = COALESCE(NEW.is_active, h.is_active)
    WHERE h.id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: mark_hosting_record_failed
-- description: marks a hosting record as failed and sets is_deleted to true
CREATE OR REPLACE FUNCTION mark_hosting_record_failed() RETURNS TRIGGER AS $$
DECLARE
    v_result_message TEXT;
BEGIN
    -- Step 1: Get the result_message from the job
    SELECT result_message INTO v_result_message
    FROM job
    WHERE id = NEW.job_id;

    UPDATE ONLY hosting
    SET
        hosting_status_id = tc_id_from_name('hosting_status', 'Failed'),
        is_deleted = TRUE,
        status_reason = v_result_message
    WHERE id = NEW.hosting_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;