-- function: plan_create_contact_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_contact_provision_contact() RETURNS TRIGGER AS $$
BEGIN

    -- thanks to the magic from inheritance, the contact table already
    -- contains the data, we just need to materialize it there.
    INSERT INTO contact (SELECT c.* FROM contact c JOIN order_item_create_contact oicc ON  c.id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);
    INSERT INTO contact_postal (SELECT cp.* FROM contact_postal cp JOIN order_item_create_contact oicc ON  cp.contact_id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);
    INSERT INTO contact_attribute (SELECT ca.* FROM contact_attribute ca JOIN order_item_create_contact oicc ON  ca.contact_id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);

    -- complete the order item
    UPDATE create_contact_plan
    SET status_id = tc_id_from_name('order_item_plan_status','completed')
    WHERE id = NEW.id;

    RETURN NEW;
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
               at.accreditation_id,
               get_tld_setting(
                       p_key=>'tld.contact.registrant_contact_update_restricted_fields',
                       p_accreditation_tld_id=>d.accreditation_tld_id
               )::TEXT[] AS registrant_contact_update_restricted_fields,
               get_tld_setting(
                       p_key=>'tld.contact.is_contact_update_supported',
                       p_accreditation_tld_id=>d.accreditation_tld_id
               )::BOOL AS is_contact_update_supported
        FROM domain_contact dc
                 JOIN domain d ON d.id = dc.domain_id
                 JOIN accreditation_tld at ON at.id =accreditation_tld_id
        WHERE dc.contact_id = v_update_contact.contact_id
        LOOP
            IF v_pcu_id IS NULL THEN
                WITH pcu_ins AS (
                    INSERT INTO provision_contact_update (
                                                          tenant_customer_id,
                                                          order_metadata,
                                                          contact_id,
                                                          order_contact_id,
                                                          order_item_plan_ids
                        ) VALUES (
                                     v_update_contact.tenant_customer_id,
                                     v_update_contact.order_metadata,
                                     v_update_contact.contact_id,
                                     v_update_contact.order_contact_id,
                                     ARRAY [NEW.id]
                                 ) RETURNING id
                )
                SELECT id INTO v_pcu_id FROM pcu_ins;
            END IF;
            IF (_contact.type = 'registrant' AND
                check_contact_field_changed_in_order_contact(
                        v_update_contact.order_contact_id,
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
                        order_contact_id,
                        accreditation_id,
                        handle,
                        status_id,
                        provision_contact_update_id
                    ) VALUES (
                                 v_update_contact.tenant_customer_id,
                                 v_update_contact.contact_id,
                                 v_update_contact.order_contact_id,
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
                    order_contact_id,
                    accreditation_id,
                    handle,
                    provision_contact_update_id
                ) VALUES (
                             v_update_contact.tenant_customer_id,
                             v_update_contact.contact_id,
                             v_update_contact.order_contact_id,
                             _contact.accreditation_id,
                             _contact.handle,
                             v_pcu_id
                         ) ON CONFLICT DO NOTHING;
            END IF;
        END LOOP;

    -- No domains linked to this contact, update contact and mark as done.
    IF NOT FOUND THEN
        -- update contact
        PERFORM update_contact_using_order_contact(v_update_contact.contact_id, v_update_contact.order_contact_id);

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


-- function: plan_delete_contact_provision()
-- description: delete a contact based on the plan
CREATE OR REPLACE FUNCTION plan_delete_contact_provision() RETURNS TRIGGER AS $$
DECLARE
    v_pcd_id            UUID;
    v_delete_contact    RECORD;
    _contact            RECORD;
BEGIN
    SELECT * INTO v_delete_contact FROM v_order_delete_contact v WHERE v.order_item_id = NEW.order_item_id;
    WITH pcd_ins AS (
        INSERT INTO provision_contact_delete (
                                              parent_id,
                                              accreditation_id,
                                              tenant_customer_id,
                                              order_metadata,
                                              contact_id,
                                              order_item_plan_ids
            ) VALUES (
                         NULL,
                         NULL,
                         v_delete_contact.tenant_customer_id,
                         v_delete_contact.order_metadata,
                         v_delete_contact.contact_id,
                         ARRAY [NEW.id]
                     ) RETURNING id
    )
    SELECT id INTO v_pcd_id FROM pcd_ins;

    FOR _contact IN SELECT * FROM ONLY provision_contact WHERE contact_id=v_delete_contact.contact_id
        LOOP
            INSERT INTO provision_contact_delete(
                parent_id,
                tenant_customer_id,
                contact_id,
                accreditation_id,
                handle
            ) VALUES (
                         v_pcd_id,
                         v_delete_contact.tenant_customer_id,
                         v_delete_contact.contact_id,
                         _contact.accreditation_id,
                         _contact.handle
                     ) ON CONFLICT DO NOTHING;
        END LOOP;
    IF NOT FOUND THEN
        PERFORM delete_contact(v_delete_contact.contact_id);
        UPDATE delete_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    end if;

    UPDATE provision_contact_delete SET is_complete = TRUE WHERE id = v_pcd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
