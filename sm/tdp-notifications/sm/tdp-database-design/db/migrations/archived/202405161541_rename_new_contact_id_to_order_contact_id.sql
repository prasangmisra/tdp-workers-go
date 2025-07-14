-- rename new_contact_id to order_contact_id in update contact flow
DO $$
BEGIN
    IF EXISTS(SELECT * FROM information_schema.columns  WHERE table_name='order_item_update_contact' and column_name='new_contact_id')
    THEN
        -- rename column in order_item_update_contact
        ALTER TABLE order_item_update_contact RENAME COLUMN new_contact_id TO order_contact_id;

        -- update view
        DROP VIEW IF EXISTS v_order_update_contact CASCADE;
        CREATE OR REPLACE VIEW v_order_update_contact AS
        SELECT
            uc.id AS order_item_id,
            uc.order_id AS order_id,
            uc.contact_id AS contact_id,
            uc.order_contact_id AS order_contact_id,
            uc.reuse_behavior AS reuse_behavior,
            o.metadata AS order_metadata,
            o.tenant_customer_id,
            o.type_id,
            o.customer_user_id,
            o.status_id,
            s.name AS status_name,
            s.descr AS status_descr,
            tc.tenant_id,
            tc.customer_id,
            tc.tenant_name,
            tc.name,
            tc_name_from_id('contact_type',ct.id) AS contact_type,
            cp.first_name,
            cp.last_name,
            cp.org_name
        FROM order_item_update_contact uc
            JOIN order_contact oc ON oc.id = uc.order_contact_id
            JOIN contact_type ct ON ct.id = oc.type_id
            LEFT JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
            JOIN "order" o ON o.id=uc.order_id
            JOIN v_order_type ot ON ot.id = o.type_id
            JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
            JOIN order_status s ON s.id = o.status_id
        ;
    END IF;

    IF EXISTS(SELECT * FROM information_schema.columns  WHERE table_name='provision_contact_update' and column_name='new_contact_id')
    THEN
        -- rename column in provision_contact_update
        ALTER TABLE provision_contact_update RENAME COLUMN new_contact_id TO order_contact_id;
    END IF;

    IF EXISTS(SELECT * FROM information_schema.columns  WHERE table_name='provision_domain_contact_update' and column_name='new_contact_id')
    THEN
        -- rename column in provision_domain_contact_update
        ALTER TABLE provision_domain_contact_update RENAME COLUMN new_contact_id TO order_contact_id;
    END IF;
END $$;

-- rename references in plan_update_contact_provision

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

-- rename references in provision_contact_update_job

-- function: provision_contact_update_job()
-- description: creates contact update parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_update_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_job          RECORD;
    v_contact           RECORD;
BEGIN

    SELECT job_create(
        NEW.tenant_customer_id,
        'provision_contact_update',
        NEW.id,
        to_jsonb(NULL::jsonb)
    ) INTO _parent_job_id;

    UPDATE provision_contact_update SET job_id= _parent_job_id
    WHERE id = NEW.id;

    FOR _child_job IN
    SELECT pdcu.*
    FROM provision_domain_contact_update pdcu
    JOIN provision_status ps ON ps.id = pdcu.status_id
    WHERE pdcu.provision_contact_update_id = NEW.id AND
          ps.id = tc_id_from_name('provision_status','pending')
    LOOP
        SELECT
            _child_job.id AS provision_domain_contact_update_id,
            _child_job.tenant_customer_id AS tenant_customer_id,
            jsonb_get_order_contact_by_id(c.id) AS contact,
            TO_JSONB(a.*) AS accreditation,
            _child_job.handle AS handle
        INTO v_contact
        FROM ONLY order_contact c
        JOIN v_accreditation a ON  a.accreditation_id = _child_job.accreditation_id
        WHERE c.id=_child_job.order_contact_id;

        UPDATE provision_domain_contact_update SET job_id=job_submit(
            _child_job.tenant_customer_id,
            'provision_domain_contact_update',
            _child_job.id,
            to_jsonb(v_contact.*),
            _parent_job_id,
            FALSE
        ) WHERE id = _child_job.id;
    END LOOP;

    -- all child jobs are failed, fail the parent job
    IF NOT FOUND THEN
        UPDATE job
        SET status_id= tc_id_from_name('job_status', 'failed')
        WHERE id = _parent_job_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- rename references in provision_contact_update_success

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