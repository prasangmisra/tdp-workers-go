CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
BEGIN
    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;

    DELETE FROM domain_contact dc
    USING provision_domain_update_rem_contact pduc
    WHERE dc.domain_id = NEW.domain_id
      AND dc.contact_id = pduc.contact_id
      AND dc.domain_contact_type_id = pduc.contact_type_id
      AND pduc.provision_domain_update_id = NEW.id;

    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdac.contact_id,
            pdac.contact_type_id,
            pc.handle
        FROM provision_domain_update_add_contact pdac
                 JOIN provision_contact pc ON pc.contact_id = pdac.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdac.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;



    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM provision_domain_update_add_host pduah
            JOIN ONLY host h ON h.id = pduah.host_id
        WHERE pduah.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete association for removed hosts
    WITH removed_hosts AS (
        SELECT h.*
        FROM provision_domain_update_rem_host pdurh
            JOIN ONLY host h ON h.id = pdurh.host_id
        WHERE pdurh.provision_domain_update_id = NEW.id
    )
    DELETE FROM
        domain_host dh
    WHERE dh.domain_id = NEW.domain_id
        AND dh.host_id IN (SELECT id FROM removed_hosts);

    -- update auto renew flag if changed
    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info),
        secdns_max_sig_life = COALESCE(NEW.secdns_max_sig_life, d.secdns_max_sig_life)
    WHERE d.id = NEW.domain_id;

    -- update locks
    IF NEW.locks IS NOT NULL THEN
        PERFORM update_domain_locks(NEW.domain_id, NEW.locks);
    end if;

    -- handle secdns to be removed
    PERFORM remove_domain_secdns_data(
        NEW.domain_id,
        ARRAY(
            SELECT udrs.id
            FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            WHERE pdurs.provision_domain_update_id = NEW.id
        )
    );

    -- handle secdns to be added
    PERFORM add_domain_secdns_data(
        NEW.domain_id,
        ARRAY(
            SELECT udas.id
            FROM provision_domain_update_add_secdns pduas
            JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
            WHERE pduas.provision_domain_update_id = NEW.id
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_update_domain_contact     RECORD;
    _contact_exists             BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _thin_registry              BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;


    SELECT * INTO v_update_domain_contact
    FROM (
        SELECT domain_contact_type_id FROM update_domain_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id

        UNION

        SELECT domain_contact_type_id FROM update_domain_add_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id
    ) combined_results;

    -- Check if trying to add a contact type that already exists and is not being removed
    IF EXISTS (
        SELECT 1
        FROM update_domain_add_contact udac
        JOIN domain_contact dc ON dc.domain_id = v_update_domain.domain_id
            AND dc.domain_contact_type_id = udac.domain_contact_type_id
        WHERE udac.update_domain_id = NEW.order_item_id
            AND udac.order_contact_id = NEW.reference_id
            -- for registrant can be changed without removing
            AND dc.domain_contact_type_id <> tc_id_from_name('domain_contact_type', 'registrant')
            AND NOT EXISTS (
                SELECT 1 FROM update_domain_rem_contact udrc
                WHERE udrc.update_domain_id = NEW.order_item_id
                    AND udrc.domain_contact_type_id = udac.domain_contact_type_id
            )
    ) THEN
        RAISE EXCEPTION 'Cannot add contact type because it already exists and is not being removed';
    END IF;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.is_thin_registry',
        p_accreditation_tld_id=>v_update_domain.accreditation_tld_id)
    INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_update_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(is_contact_type_supported_for_tld(
        v_update_domain_contact.domain_contact_type_id,
        v_update_domain.accreditation_tld_id
    )) INTO _supported_contact_type;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            accreditation_tld_id,
            domain_contact_type_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain_contact.domain_contact_type_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        );
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE update_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;
