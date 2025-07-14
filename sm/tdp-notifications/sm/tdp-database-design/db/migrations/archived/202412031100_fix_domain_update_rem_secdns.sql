-- function: validate_rem_secdns_exists()
-- description: validate that the secdns record we are trying to remove exists
CREATE OR REPLACE FUNCTION validate_rem_secdns_exists() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM secdns_ds_data
        WHERE id IN (
            SELECT ds_data_id
            FROM domain_secdns ds
                     JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
          AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be removed does not exist';
        END IF;

    ELSE
        PERFORM 1 FROM secdns_key_data
        WHERE id IN (
            SELECT key_data_id
            FROM domain_secdns ds
                     JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
          AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be removed does not exist';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_add_secdns_does_not_exist()
-- description: validate that the secdns record we are trying to add does not exist
CREATE OR REPLACE FUNCTION validate_add_secdns_does_not_exist() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM secdns_ds_data
        WHERE id IN (
            SELECT ds_data_id
            FROM domain_secdns ds
                     JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
          AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be added already exists';
        END IF;

    ELSE
        PERFORM 1 FROM secdns_key_data
        WHERE id IN (
            SELECT key_data_id
            FROM domain_secdns ds
                     JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
          AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be added already exists';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
