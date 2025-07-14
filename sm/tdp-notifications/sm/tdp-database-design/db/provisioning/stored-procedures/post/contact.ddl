-- function: provision_contact_update_success()
-- description: updates the contact once the provision job completes
CREATE OR REPLACE FUNCTION provision_contact_update_success() RETURNS TRIGGER AS $$
DECLARE
    _item           RECORD;
    _contact_id     UUID;
BEGIN
    PERFORM TRUE FROM
        provision_domain_contact_update
    WHERE
        provision_contact_update_id = NEW.id
      AND status_id = tc_id_from_name('provision_status', 'failed');

    IF FOUND THEN
        -- create new contact
        SELECT duplicate_contact_by_id(NEW.contact_id) INTO _contact_id;

        -- update contact for failed items
        FOR _item IN
            SELECT
                *
            FROM
                provision_domain_contact_update
            WHERE
                provision_contact_update_id = NEW.id
              AND status_id = tc_id_from_name('provision_status', 'failed')
            LOOP

                UPDATE
                    domain_contact
                SET
                    contact_id = _contact_id
                WHERE
                    contact_id = _item.contact_id
                  AND handle = _item.handle;
            END LOOP;
    END IF;

    -- update contact
    PERFORM update_contact_using_order_contact(NEW.contact_id, NEW.order_contact_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_contact_delete_success()
-- description: deletes the contact once the provision job completes
CREATE OR REPLACE FUNCTION provision_contact_delete_success() RETURNS TRIGGER AS $$
BEGIN
    PERFORM delete_contact(NEW.contact_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
