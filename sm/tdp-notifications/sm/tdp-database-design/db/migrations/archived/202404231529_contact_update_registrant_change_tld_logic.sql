-- insert new tld setting
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES(
    'registrant_contact_update_restricted_fields',
    (SELECT id FROM attr_category WHERE name='contact'),
    'List of registrant fields restricted in contact update',
    (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
    ARRAY['first_name','last_name','org_name','email']::TEXT,
    TRUE
) ON CONFLICT DO NOTHING;

-- delete old setting
DELETE FROM attr_key WHERE name='is_owner_contact_change_supported';

--

-- function: check_contact_field_changed_in_order_contact()
-- description: checks if one of the passed fields in contact has changed in order contact
CREATE OR REPLACE FUNCTION check_contact_field_changed_in_order_contact(_oc_id UUID, _c_id UUID, _fields TEXT[]) RETURNS BOOLEAN AS $$
DECLARE
    _jsn_oc     JSON;
    _jsn_c      JSON;
    _c          TEXT;
BEGIN
    SELECT jsonb_get_order_contact_by_id(_oc_id)
    INTO _jsn_oc;

    SELECT jsonb_get_contact_by_id(_c_id)
    INTO _jsn_c;

    FOREACH _c IN ARRAY _fields
    LOOP
        -- check contact
        IF _jsn_oc->>_c IS DISTINCT FROM _jsn_c->>_c THEN
            RETURN TRUE;
        END IF;

        -- check contact postals
        PERFORM TRUE FROM json_array_elements((_jsn_oc->>'contact_postals')::JSON) AS ocp
                      JOIN json_array_elements((_jsn_c->>'contact_postals')::JSON) AS cp
                           ON cp->>'is_international' = ocp->>'is_international'
        WHERE ocp->>_c IS DISTINCT FROM cp->>_c;
        IF FOUND THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_contact_provision()
-- description: update a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_contact_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_contact    RECORD;
    v_pcu_id            UUID;
    _contact            RECORD;
BEGIN
    -- order information
    SELECT * INTO v_update_contact
    FROM v_order_update_contact
    WHERE order_item_id = NEW.order_item_id;

    FOR _contact IN
    SELECT dc.handle,
        tc_name_from_id('domain_contact_type',dc.domain_contact_type_id) AS type,
        vat.accreditation_id,
        va1.value::TEXT[] AS registrant_contact_update_restricted_fields,
        va2.value::BOOL AS is_contact_update_supported
    FROM domain_contact dc
    JOIN domain d ON d.id = dc.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN v_attribute va1 ON
        va1.tld_id = vat.tld_id AND
        va1.key = 'tld.contact.registrant_contact_update_restricted_fields' AND
        va1.tenant_id = vtc.tenant_id
    JOIN v_attribute va2 ON
        va2.tld_id = vat.tld_id AND
        va2.key = 'tld.contact.is_contact_update_supported' AND
        va2.tenant_id = vtc.tenant_id
    WHERE dc.contact_id = v_update_contact.contact_id
    LOOP
        IF v_pcu_id IS NULL THEN
            WITH pcu_ins AS (
                INSERT INTO provision_contact_update (
                    tenant_customer_id,
                    order_metadata,
                    contact_id,
                    new_contact_id,
                    order_item_plan_ids
                    ) VALUES (
                        v_update_contact.tenant_customer_id,
                        v_update_contact.order_metadata,
                        v_update_contact.contact_id,
                        v_update_contact.new_contact_id,
                        ARRAY [NEW.id]
                    ) RETURNING id
            )
            SELECT id INTO v_pcu_id FROM pcu_ins;
        END IF;
        IF (_contact.type = 'registrant' AND
            check_contact_field_changed_in_order_contact(
                    v_update_contact.new_contact_id,
                    v_update_contact.contact_id,
                    _contact.registrant_contact_update_restricted_fields
                )
           )
                OR NOT _contact.is_contact_update_supported THEN
            IF v_update_contact.reuse_behavior = 'fail' THEN
                -- raise exception to rollback inserted provision
                RAISE EXCEPTION 'contact update not supported';
                -- END LOOP
                EXIT;
            ELSE
                -- insert into provision_domain_contact_update with failed status
                INSERT INTO provision_domain_contact_update(
                    tenant_customer_id,
                    contact_id,
                    new_contact_id,
                    accreditation_id,
                    handle,
                    status_id,
                    provision_contact_update_id
                ) VALUES (
                    v_update_contact.tenant_customer_id,
                    v_update_contact.contact_id,
                    v_update_contact.new_contact_id,
                    _contact.accreditation_id,
                    _contact.handle,
                    tc_id_from_name('provision_status','failed'),
                    v_pcu_id
                ) ON CONFLICT (provision_contact_update_id, handle) DO UPDATE
                    SET status_id = tc_id_from_name('provision_status','failed');
            END IF;
        ELSE
            -- insert into provision_domain_contact_update with normal flow
            INSERT INTO provision_domain_contact_update(
                tenant_customer_id,
                contact_id,
                new_contact_id,
                accreditation_id,
                handle,
                provision_contact_update_id
            ) VALUES (
                v_update_contact.tenant_customer_id,
                v_update_contact.contact_id,
                v_update_contact.new_contact_id,
                _contact.accreditation_id,
                _contact.handle,
                v_pcu_id
            ) ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- No domains linked to this contact, update contact and mark as done.
    IF NOT FOUND THEN
        -- update contact
        PERFORM update_contact_using_order_contact(v_update_contact.contact_id, v_update_contact.new_contact_id);

        -- complete the order item
        UPDATE update_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- start the flow
    UPDATE provision_contact_update SET is_complete = TRUE WHERE id = v_pcu_id;
    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        -- fail plan
        UPDATE update_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','failed')
        WHERE id = NEW.id;

        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

