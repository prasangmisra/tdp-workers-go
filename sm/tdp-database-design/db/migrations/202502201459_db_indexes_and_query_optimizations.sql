--- New indexes
CREATE INDEX IF NOT EXISTS job_reference_id_idx ON job(reference_id);
CREATE INDEX IF NOT EXISTS order_item_order_id_idx ON order_item(order_id);
CREATE INDEX IF NOT EXISTS order_item_parent_order_item_id_idx ON order_item(parent_order_item_id);

--- domain
CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
    v_period_hours  INTEGER;
BEGIN

    IF NEW.expiry_date IS NULL THEN

        SELECT get_tld_setting(
                       p_key => 'tld.lifecycle.' || tc_name_from_id('rgp_status', NEW.status_id),
                       p_accreditation_tld_id=> d.accreditation_tld_id
               ) INTO v_period_hours
        FROM domain d
        WHERE d.id = NEW.domain_id;

        NEW.expiry_date = NOW() + (v_period_hours || ' hours')::INTERVAL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Order

-- f_order_item_plan: simulates parameterized view
-- gets all order_item_plan records in hierarchical structure for given order item
CREATE OR REPLACE FUNCTION f_order_item_plan(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                       UUID,
                     id                             UUID,
                     parent_id                      UUID,
                     order_item_id                  UUID,
                     plan_status_id                 UUID,
                     object_id                      UUID,
                     plan_status_name               TEXT,
                     plan_status_is_success         BOOLEAN,
                     plan_status_is_final           BOOLEAN,
                     plan_validation_status_name    TEXT,
                     object_name                    TEXT,
                     reference_id                   UUID,
                     result_message                 TEXT,
                     provision_order                INT,
                     parent_object_id               UUID
                 )
AS $$
BEGIN
    RETURN QUERY
        WITH RECURSIVE plan AS (
            SELECT
                order_item_plan.*,
                NULL::uuid   AS parent_object_id
            FROM order_item_plan
            WHERE order_item_plan.parent_id IS NULL AND order_item_plan.order_item_id = p_order_item_id
            UNION ALL  -- Using UNION ALL since duplicates are impossible
            SELECT
                order_item_plan.*,
                plan.order_item_object_id as parent_object_id
            FROM order_item_plan
                     INNER JOIN plan on order_item_plan.parent_id = plan.id
            WHERE order_item_plan.order_item_id = p_order_item_id
        )
        SELECT
            oi.order_id AS order_id,
            p.id AS id,
            p.parent_id AS parent_id,
            p.order_item_id AS order_item_id,
            s.id AS plan_status_id,
            obj.id AS object_id,
            s.name AS plan_status_name,
            s.is_success AS plan_status_is_success,
            s.is_final AS plan_status_is_final,
            vs.name AS plan_validation_status_name,
            obj.name AS object_name,
            p.reference_id AS reference_id,
            p.result_message,
            p.provision_order,
            p.parent_object_id
        FROM plan p
                 JOIN order_item_object obj ON obj.id = p.order_item_object_id
                 JOIN order_item_plan_status s ON s.id = p.status_id
                 JOIN order_item_plan_validation_status vs ON vs.id = p.validation_status_id
                 JOIN order_item oi ON oi.id = p.order_item_id
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;

-- f_order_item_plan_status: simulates parameterized view
-- gets a status summary for all order_item_plan records for a given order item
CREATE OR REPLACE FUNCTION f_order_item_plan_status(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                UUID,
                     order_item_id           UUID,
                     provision_order         INT,
                     total                   BIGINT,
                     total_new               BIGINT,
                     total_validated         BIGINT,
                     total_success           BIGINT,
                     total_fail              BIGINT,
                     total_processing        BIGINT,
                     objects                 TEXT[],
                     object_ids              UUID[],
                     order_item_plan_ids     UUID[]
                 )
AS $$
BEGIN
    RETURN QUERY
        SELECT
            p.order_id,
            p.order_item_id,
            p.provision_order,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE p.plan_status_name='new') AS total_new,
            COUNT(*) FILTER (WHERE p.plan_validation_status_name='completed') AS total_validated,
            COUNT(*) FILTER (WHERE p.plan_status_is_success AND p.plan_status_is_final) AS total_success,
            COUNT(*) FILTER (WHERE NOT p.plan_status_is_success AND p.plan_status_is_final ) AS total_fail,
            COUNT(*) FILTER (WHERE p.plan_status_name='processing' ) AS total_processing,
            ARRAY_AGG(p.object_name) AS objects,
            ARRAY_AGG(p.object_id) AS object_ids,
            ARRAY_AGG(p.id) AS order_item_plan_ids
        FROM f_order_item_plan(p_order_item_id) p
        GROUP BY 1,2,3;
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

-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    _contact_exists             BOOLEAN;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

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
                   p_key => 'tld.lifecycle.is_thin_registry',
                   p_accreditation_tld_id => v_create_domain.accreditation_tld_id
           ) INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_create_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(supported_contact_type) INTO _supported_contact_type
    FROM (
             SELECT is_contact_type_supported_for_tld(
                            domain_contact_type_id,
                            v_create_domain.accreditation_tld_id
                    ) AS supported_contact_type
             FROM create_domain_contact
             WHERE order_contact_id = NEW.reference_id
               AND create_domain_id = NEW.order_item_id
         ) AS sct;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
                   NEW.reference_id,
                   v_create_domain.accreditation_id,
                   v_create_domain.tenant_customer_id,
                   ARRAY[NEW.id],
                   v_create_domain.order_metadata
               );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    _contact_exists             BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _thin_registry              BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

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
    SELECT BOOL_OR(supported_contact_type) INTO _supported_contact_type
    FROM (
             SELECT is_contact_type_supported_for_tld(
                            domain_contact_type_id,
                            v_update_domain.accreditation_tld_id
                    ) AS supported_contact_type
             FROM update_domain_contact
             WHERE order_contact_id = NEW.reference_id
               AND update_domain_id = NEW.order_item_id
         ) AS sct;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
                   NEW.reference_id,
                   v_update_domain.accreditation_id,
                   v_update_domain.tenant_customer_id,
                   ARRAY[NEW.id],
                   v_update_domain.order_metadata
               );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_plan_start()
-- description: this is triggered when the order goes from new to pending
-- and is in charge of updating the items and setting status 'processing'
-- only if all order item plans are ready (no validation needed)
CREATE OR REPLACE FUNCTION order_item_plan_start() RETURNS TRIGGER AS $$
DECLARE
    v_strategy      RECORD;
BEGIN

    -- start validation if needed
    UPDATE order_item_plan
    SET validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'started')
    WHERE order_item_id = NEW.id
      AND validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'pending');

    IF NOT FOUND THEN
        -- start plan execution if nothing to validate

        SELECT * INTO v_strategy
        FROM f_order_item_plan_status(NEW.id)
        WHERE total_new > 0
        LIMIT 1;

        IF FOUND THEN
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','processing')
            WHERE
                order_item_id=NEW.id
              AND status_id=tc_id_from_name('order_item_plan_status','new')
              AND order_item_object_id = ANY(v_strategy.object_ids)
              AND provision_order = v_strategy.provision_order;
        ELSE

            RAISE NOTICE 'order processing has ended';

        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: order_item_plan_ready()
CREATE OR REPLACE FUNCTION order_item_plan_validated() RETURNS TRIGGER AS $$
DECLARE
    is_validated    BOOLEAN;
    v_strategy      RECORD;
BEGIN

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

    IF NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','failed') THEN

        WITH job_data AS (
            SELECT result_data, result_message
            FROM job
            WHERE reference_id = NEW.id
            LIMIT 1
        )
        UPDATE order_item_plan
        SET
            result_data = job_data.result_data,
            result_message = COALESCE(job_data.result_message, order_item_plan.result_message)
        FROM job_data
        WHERE order_item_plan.id = NEW.id;

        -- fail order if at least one plan item failed
        PERFORM order_item_plan_fail(NEW.order_item_id);

        RETURN NEW;
    END IF;

    SELECT SUM(total_validated) = SUM(total)
    INTO is_validated
    FROM f_order_item_plan_status(NEW.order_item_id);

    IF is_validated THEN
        -- start processing of plan if everything is validated

        SELECT * INTO v_strategy
        FROM f_order_item_plan_status(NEW.order_item_id)
        WHERE total_new > 0
        LIMIT 1;

        IF FOUND THEN
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','processing')
            WHERE
                order_item_id=NEW.order_item_id
              AND status_id=tc_id_from_name('order_item_plan_status','new')
              AND order_item_object_id = ANY(v_strategy.object_ids)
              AND provision_order = v_strategy.provision_order;
        ELSE

            -- nothing to do after validation; everything was skipped
            UPDATE order_item
            SET status_id = (SELECT id FROM order_item_status WHERE is_final AND is_success)
            WHERE id = NEW.order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_plan_processed()
CREATE OR REPLACE FUNCTION order_item_plan_processed() RETURNS TRIGGER AS $$
DECLARE
    v_strategy      RECORD;
    v_new_strategy  RECORD;
BEGIN

    -- RAISE NOTICE 'placing lock on related rows...';

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

    -- check to see if we are waiting for any other object
    SELECT * INTO v_strategy
    FROM f_order_item_plan_status(NEW.order_item_id)
    WHERE
        NEW.id = ANY(order_item_plan_ids)
    LIMIT 1;


    IF v_strategy.total_fail > 0 THEN
        -- fail order if at least one plan item failed

        PERFORM order_item_plan_fail(NEW.order_item_id);

        RETURN NEW;
    END IF;

    -- if no failures, we need to check and see if there's anything pending
    IF v_strategy.total_processing > 0 THEN
        -- RAISE NOTICE 'Waiting. for other objects to complete (id: %s) remaining: %',NEW.id,v_strategy.total_processing;
        RETURN NEW;
    END IF;

    IF v_strategy.total_success = v_strategy.total THEN

        SELECT *
        INTO v_new_strategy
        FROM f_order_item_plan_status(NEW.order_item_id)
        WHERE total_new > 0
        LIMIT 1;

        IF NOT FOUND THEN

            -- nothing more to do, we can mark the order as complete!
            UPDATE order_item
            SET status_id = (SELECT id FROM order_item_status WHERE is_final AND is_success)
            WHERE id = NEW.order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

        ELSE

            -- this should trigger the provisioning of the objects on the next object group
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','processing')
            WHERE
                order_item_id=NEW.order_item_id
              AND status_id=tc_id_from_name('order_item_plan_status','new')
              AND order_item_object_id = ANY(v_new_strategy.object_ids);

            RAISE NOTICE 'Order %: processing objects of type %',v_new_strategy.order_id,v_new_strategy.objects;

        END IF;

    END IF;

    RAISE NOTICE 'nothing else to do';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: check_if_tld_supports_host_object()
-- description: checks if tld supports host object or not
CREATE OR REPLACE FUNCTION check_if_tld_supports_host_object(order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_host_object_supported  BOOLEAN;
BEGIN
    SELECT get_tld_setting(
                   p_key=>'tld.order.host_object_supported',
                   p_accreditation_tld_id=>d.accreditation_tld_id)
    INTO v_host_object_supported
    FROM order_host oh
             JOIN domain d ON d.id = oh.domain_id
    WHERE oh.id = order_host_id;

    IF NOT v_host_object_supported THEN
        IF order_type = 'create' THEN
            RAISE EXCEPTION 'Host create not supported';
        ELSE
            RAISE EXCEPTION 'Host update not supported; use domain update on parent domain';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- function: order_set_metadata()
-- description: Update order metadata by adding order id;
CREATE OR REPLACE FUNCTION order_set_metadata() RETURNS TRIGGER AS $$
BEGIN
    NEW.metadata = COALESCE(NEW.metadata, '{}'::jsonb) || JSONB_BUILD_OBJECT ('order_id', NEW.id);
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_set_metadata_tg ON "order";
CREATE OR REPLACE TRIGGER order_set_metadata_tg
    BEFORE INSERT ON "order"
    FOR EACH ROW  WHEN (NOT is_data_migration() ) EXECUTE PROCEDURE order_set_metadata();


-- provision

CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
    v_domain_secdns_id UUID;
BEGIN
    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        auto_renew,
        secdns_max_sig_life,
        uname,
        language,
        tags,
        metadata
    ) (
        SELECT
            pd.id,    -- domain id
            pd.tenant_customer_id,
            pd.accreditation_tld_id,
            pd.domain_name,
            pd.pw,
            pd.roid,
            COALESCE(pd.ry_created_date,pd.created_date),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            pd.auto_renew,
            pd.secdns_max_sig_life,
            COALESCE(pd.uname,pd.domain_name),
            pd.language,
            pd.tags,
            pd.metadata
        FROM provision_domain pd
        WHERE id = NEW.id
    );

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            pdc.provision_domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdc.provision_domain_id = NEW.id
    );

    -- host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            provision_domain_id,
            host_id
        FROM provision_domain_host
        WHERE provision_domain_id = NEW.id
    );

    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
                 NEW.id,
                 tc_id_from_name('rgp_status', 'add_grace_period')
             );

    -- secdns data
    WITH key_data AS (
        INSERT INTO secdns_key_data
            (
                SELECT
                    oskd.*
                FROM provision_domain_secdns pds
                         JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                         JOIN order_secdns_key_data oskd ON oskd.id = cds.key_data_id
                WHERE pds.provision_domain_id = NEW.id
            ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
            (
                SELECT
                    oskd.*
                FROM provision_domain_secdns pds
                         JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                         JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                         JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
                WHERE pds.provision_domain_id = NEW.id
            ) RETURNING id
    ), ds_data AS (
        INSERT INTO secdns_ds_data
            (
                SELECT
                    osdd.id,
                    osdd.key_tag,
                    osdd.algorithm,
                    osdd.digest_type,
                    osdd.digest,
                    dkd.id AS key_data_id
                FROM provision_domain_secdns pds
                         JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                         JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                         LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
                WHERE pds.provision_domain_id = NEW.id
            ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.id, NULL, id FROM key_data

        UNION ALL

        SELECT NEW.id, id, NULL FROM ds_data
    );

    -- start the provision domain update
    IF NEW.parent_id IS NOT NULL THEN
        UPDATE provision_domain_update
        SET is_complete = TRUE, domain_id = NEW.id
        WHERE id = NEW.parent_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
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
    ) ON CONFLICT (domain_id, domain_contact_type_id)
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


-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
    _parent_job_id      UUID;
    v_locks_required_changes JSONB;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
                       JSONB_BUILD_OBJECT(
                               'type', ct.name,
                               'handle', pc.handle
                       )
               ) AS data
        FROM provision_domain_update_contact pdc
                 JOIN domain_contact_type ct ON ct.id = pdc.contact_type_id
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
                 JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final AND pc.accreditation_id = NEW.accreditation_id
          AND pdc.provision_domain_update_id = NEW.id
    ), hosts_add AS(
        SELECT JSONB_AGG(data) AS add
        FROM (
                 SELECT
                     JSON_BUILD_OBJECT(
                             'name', h.name,
                             'ip_addresses', JSONB_AGG(ha.address)
                     ) AS data
                 FROM provision_domain_update_add_host pduah
                          JOIN ONLY host h ON h.id = pduah.host_id
                          LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
                 WHERE pduah.provision_domain_update_id = NEW.id
                 GROUP BY h.name
             ) sub_q
    ), hosts_rem AS(
        SELECT  JSONB_AGG(data) AS rem
        FROM (
                 SELECT
                     JSON_BUILD_OBJECT(
                             'name', h.name,
                             'ip_addresses', JSONB_AGG(ha.address)
                     ) AS data
                 FROM provision_domain_update_rem_host pdurh
                          JOIN ONLY host h ON h.id = pdurh.host_id
                          LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
                 WHERE pdurh.provision_domain_update_id = NEW.id
                 GROUP BY h.name
             ) sub_q
    ), secdns_add AS(
        SELECT
                    JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                            'key_tag', osdd.key_tag,
                            'algorithm', osdd.algorithm,
                            'digest_type', osdd.digest_type,
                            'digest', osdd.digest,
                            'key_data',
                            CASE
                                WHEN osdd.key_data_id IS NOT NULL THEN
                                    JSONB_BUILD_OBJECT(
                                            'flags', oskd2.flags,
                                            'protocol', oskd2.protocol,
                                            'algorithm', oskd2.algorithm,
                                            'public_key', oskd2.public_key
                                    )
                                END
                    )
                             ) FILTER (WHERE udas.ds_data_id IS NOT NULL) AS ds_data,
                    JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                            'flags', oskd1.flags,
                            'protocol', oskd1.protocol,
                            'algorithm', oskd1.algorithm,
                            'public_key', oskd1.public_key
                    )
                             ) FILTER (WHERE udas.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_add_secdns pduas
                 LEFT JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                 LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                 LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udas.key_data_id
                 LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pduas.provision_domain_update_id = NEW.id
        GROUP BY pduas.provision_domain_update_id
    ), secdns_rem AS(
        SELECT
                    JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                            'key_tag', osdd.key_tag,
                            'algorithm', osdd.algorithm,
                            'digest_type', osdd.digest_type,
                            'digest', osdd.digest,
                            'key_data',
                            CASE
                                WHEN osdd.key_data_id IS NOT NULL THEN
                                    JSONB_BUILD_OBJECT(
                                            'flags', oskd2.flags,
                                            'protocol', oskd2.protocol,
                                            'algorithm', oskd2.algorithm,
                                            'public_key', oskd2.public_key
                                    )
                                END
                    )
                             ) FILTER (WHERE udrs.ds_data_id IS NOT NULL) AS ds_data,
                    JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                            'flags', oskd1.flags,
                            'protocol', oskd1.protocol,
                            'algorithm', oskd1.algorithm,
                            'public_key', oskd1.public_key
                    )
                             ) FILTER (WHERE udrs.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_rem_secdns pdurs
                 LEFT JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
                 LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
                 LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udrs.key_data_id
                 LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pdurs.provision_domain_update_id = NEW.id
        GROUP BY pdurs.provision_domain_update_id
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.order_metadata,
        d.domain_name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        TO_JSONB(hosts_add) || TO_JSONB(hosts_rem) AS nameservers,
        JSONB_BUILD_OBJECT(
                'max_sig_life', d.secdns_max_sig_life,
                'add', TO_JSONB(secdns_add),
                'rem', TO_JSONB(secdns_rem)
        ) as secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata,
        (lock_attrs.lock_support->>'tld.order.is_rem_update_lock_with_domain_content_supported')::boolean AS is_rem_update_lock_with_domain_content_supported,
        (lock_attrs.lock_support->>'tld.order.is_add_update_lock_with_domain_content_supported')::boolean AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
             LEFT JOIN contacts ON TRUE
             LEFT JOIN hosts_add ON TRUE
             LEFT JOIN hosts_rem ON TRUE
             LEFT JOIN secdns_add ON TRUE
             LEFT JOIN secdns_rem ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
             JOIN LATERAL (
        SELECT jsonb_object_agg(key, value) AS lock_support
        FROM v_attribute va
        WHERE va.accreditation_tld_id = d.accreditation_tld_id
          AND va.key IN (
                         'tld.order.is_rem_update_lock_with_domain_content_supported',
                         'tld.order.is_add_update_lock_with_domain_content_supported'
            )
        ) lock_attrs ON true
    WHERE d.id = NEW.id;

    -- Retrieves the required changes for domain locks based on the provided lock configuration.
    SELECT
        JSONB_OBJECT_AGG(
                l.key, l.value::BOOLEAN
        )
    INTO v_locks_required_changes
    FROM JSONB_EACH(NEW.locks) l
             LEFT JOIN v_domain_lock vdl ON vdl.name = l.key AND vdl.domain_id = NEW.domain_id AND NOT vdl.is_internal
    WHERE (NOT l.value::boolean AND vdl.id IS NOT NULL) OR (l.value::BOOLEAN AND vdl.id IS NULL);

    -- If there are required changes for the 'update' lock AND there are other changes to the domain, THEN we MAY need to
    -- create two separate jobs: One job for the 'update' lock and Another job for all other domain changes, Because if
    -- the only change we have is 'update' lock, we can do it in a single job
    IF (v_locks_required_changes ? 'update') AND
       (COALESCE(v_domain.contacts,v_domain.nameservers,v_domain.pw::JSONB)  IS NOT NULL
           OR NOT is_jsonb_empty_or_null(v_locks_required_changes - 'update'))
    THEN
        -- If 'update' lock has false value (remove the lock) and the registry "DOES NOT" support removing that lock with
        -- the other domain changes in a single command, then we need to create two jobs: the first one to remove the
        -- domain lock, and the second one to handle the other domain changes
        IF (v_locks_required_changes->'update')::BOOLEAN IS FALSE AND
           NOT v_domain.is_rem_update_lock_with_domain_content_supported THEN
            -- all the changes without the update lock removal, because first we need to remove the lock on update
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update')
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- first remove the update lock so we can do the other changes
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    jsonb_build_object('locks', jsonb_build_object('update', FALSE),
                                       'name',v_domain.name,
                                       'accreditation',v_domain.accreditation,
                                       'accreditation_tld', v_domain.accreditation_tld),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN

        -- Same thing here, if 'update' lock has true value (add the lock) and the registry DOES NOT support adding that
        -- lock with the other domain changes in a single command, then we need to create two jobs: the first one to
        -- handle the other domain changes and the second one to add the domain lock

        elsif (v_locks_required_changes->'update')::BOOLEAN IS TRUE AND
              NOT v_domain.is_add_update_lock_with_domain_content_supported THEN
            -- here we want to add the lock on update (we will do the changes first then add the lock)
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           jsonb_build_object('locks', jsonb_build_object('update', TRUE),
                                              'name',v_domain.name,
                                              'accreditation',v_domain.accreditation)
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- Submit child job for all the changes other than domain update lock
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update'),
                    _parent_job_id
                    );

            RETURN NEW; -- RETURN
        end if;
    end if;
    UPDATE provision_domain_update SET
        job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_update',
                NEW.id,
                TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes)
                 ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION provision_finish() RETURNS TRIGGER AS $$
DECLARE
    v_status      RECORD;
BEGIN

    SELECT * INTO v_status FROM provision_status WHERE id = NEW.status_id;

    IF NOT v_status.is_final THEN
        RETURN NEW;
    END IF;

    -- notify all the order_item_plan_ids that are pending
    IF NEW.order_item_plan_ids IS NOT NULL THEN
        -- Pre-cache values from job table once
        WITH job_data AS (
            SELECT result_data, result_message
            FROM job
            WHERE id = NEW.job_id
        )
        UPDATE order_item_plan
        SET
            status_id = (
                SELECT id
                FROM order_item_plan_status
                WHERE is_success = v_status.is_success
                  AND is_final
            ),
            result_data = COALESCE(NEW.result_data, (SELECT result_data FROM job_data)),
            result_message = COALESCE(NEW.result_message, (SELECT result_message FROM job_data))
        WHERE id = ANY(NEW.order_item_plan_ids);
    END IF;

    IF v_status.is_success THEN
        EXECUTE 'UPDATE ' || TG_TABLE_NAME || ' SET provisioned_date=NOW() WHERE id = $1'
            USING NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- tld settings

CREATE OR REPLACE FUNCTION get_tld_setting(
    p_key TEXT,
    p_accreditation_tld_id UUID DEFAULT NULL,
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_tenant_id UUID DEFAULT NULL,
    p_tenant_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _tld_setting    TEXT;
    v_tld_id        UUID;
    v_tenant_id     UUID;
BEGIN
    -- Determine the TLD ID
    IF p_tld_id IS NOT NULL AND v_tld_id IS NULL THEN
        v_tld_id := p_tld_id;
    ELSIF p_tld_name IS NOT NULL AND v_tld_id IS NULL THEN
        SELECT id INTO v_tld_id FROM tld WHERE name = p_tld_name;
        IF v_tld_id IS NULL THEN
            RAISE NOTICE 'No TLD found for name %', p_tld_name;
            RETURN NULL;
        END IF;
    ELSEIF p_accreditation_tld_id IS NULL THEN
        RAISE NOTICE 'At least one of the following must be provided: TLD ID/name or accreditation_tld ID';
        RETURN NULL;
    END IF;

    -- Determine the Tenant ID
    IF p_tenant_id IS NOT NULL THEN
        v_tenant_id := p_tenant_id;
    ELSIF p_tenant_name IS NOT NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM v_tenant_customer WHERE tenant_name = p_tenant_name;
        IF v_tenant_id IS NULL THEN
            RAISE NOTICE 'No tenant found for name %', p_tenant_name;
            RETURN NULL;
        END IF;
    END IF;

    -- Determine the TLD ID/Tenant ID from accreditation tld id
    IF p_accreditation_tld_id IS NOT NULL AND v_tld_id IS NULL AND v_tenant_id IS NULL THEN
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.accreditation_tld_id = p_accreditation_tld_id;
        RETURN _tld_setting;
    END IF;

    -- Retrieve the setting value from the v_attribute
    IF v_tenant_id IS NOT NULL THEN
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id
          AND va.tenant_id = v_tenant_id;
    ELSE
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id;
    END IF;

    -- Check if a setting was found
    IF _tld_setting IS NULL THEN
        RAISE NOTICE 'No setting found for key %, TLD ID %, and tenant ID %', p_key, v_tld_id, v_tenant_id;
        RETURN NULL;
    ELSE
        RETURN _tld_setting;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- views
DROP VIEW IF EXISTS v_attribute CASCADE;
CREATE OR REPLACE VIEW v_attribute AS

WITH RECURSIVE categories AS (
    SELECT id, name, descr, name AS parent_attr_category FROM attr_category WHERE parent_id IS NULL
    UNION
    SELECT c.id, p.name || '.' || c.name, c.descr, p.name AS parent_attr_category FROM attr_category c JOIN categories p ON p.id = c.parent_id
)

SELECT DISTINCT
    vat.tenant_id,
    vat.tenant_name,
    vat.tld_name AS tld_name,
    vat.tld_id AS tld_id,
    vat.accreditation_tld_id,
    c.name AS path,
    c.id AS category_id,
    c.parent_attr_category,
    k.id AS key_id,
    avt.data_type,
    avt.name AS data_type_name,
    c.name || '.' || k.name AS key,
    COALESCE(vtld.value,vpi.value,vp.value,vpr.value,v.value,k.default_value) AS value,
    COALESCE(vtld.is_default,vpi.is_default,vp.is_default,vpr.is_default,v.is_default,TRUE) AS is_default
FROM v_accreditation_tld vat
         JOIN categories c ON TRUE
         JOIN attr_key k ON k.category_id = c.id
         JOIN attr_value_type avt ON avt.id = k.value_type_id
         LEFT JOIN v_attr_value v
                   ON  v.tenant_id = vat.tenant_id
                       AND v.key_id = k.id
                       AND COALESCE(v.tld_id,v.provider_instance_id,v.provider_id,v.registry_id) IS NULL
         LEFT JOIN v_attr_value vtld ON vtld.key_id = k.id AND vat.tld_id = vtld.tld_id AND vat.tenant_id = vtld.tenant_id
         LEFT JOIN v_attr_value vpi ON vpi.key_id = k.id AND vat.provider_instance_id = vpi.provider_instance_id
         LEFT JOIN v_attr_value vp ON vp.key_id = k.id AND vat.provider_id = vp.provider_id
         LEFT JOIN v_attr_value vpr ON vpr.key_id = k.id AND vat.registry_id = vpr.registry_id;


-------------------------
CREATE OR REPLACE FUNCTION maintain_audit_trail() RETURNS trigger AS
$$
DECLARE
    v_table TEXT;
    v_hnew hstore;
    v_hold hstore;
    v_changes hstore;
    v_id UUID;
BEGIN
    -- Get base table name for partitioned tables
    v_table := regexp_replace(TG_TABLE_NAME, '_[0-9]{6}$', '');

    CASE TG_OP
        WHEN 'INSERT' THEN
            v_hnew := hstore(NEW);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hnew->'id')::uuid;

            INSERT INTO audit_trail_log (
                created_by,
                table_name,
                operation,
                object_id,
                new_value,
                statement_date
            ) VALUES (
                                 current_user,
                                 v_table,
                                 TG_OP,
                                 v_id,
                                 v_hnew,
                                 clock_timestamp()
                     );
            RETURN NEW;

        WHEN 'DELETE' THEN
            v_hold := hstore(OLD);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hold->'id')::uuid;

            INSERT INTO audit_trail_log (
                created_by,
                table_name,
                operation,
                object_id,
                old_value,
                statement_date
            ) VALUES (
                                 current_user,
                                 v_table,
                                 TG_OP,
                                 v_id,
                                 v_hold,
                                 clock_timestamp()
                     );
            RETURN OLD;

        WHEN 'UPDATE' THEN
            v_hold := hstore(OLD);
            v_hnew := hstore(NEW);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hnew->'id')::uuid;

            -- Calculate changes
            v_changes := v_hnew - v_hold;

            -- Only log if there are non-update-timestamp changes
            IF v_changes != ''::hstore AND
               EXISTS (
                   SELECT 1
                   FROM EACH(v_changes) AS t(k,v)
                   WHERE k !~* '^updated_'
               ) THEN
                INSERT INTO audit_trail_log (
                    created_by,
                    table_name,
                    operation,
                    object_id,
                    old_value,
                    new_value,
                    statement_date
                ) VALUES (
                                     current_user,
                                     v_table,
                                     TG_OP,
                                     v_id,
                                     v_hold,
                                     v_changes,
                                     clock_timestamp()
                         );
            END IF;
            RETURN NEW;
        END CASE;
END;
$$
    LANGUAGE plpgsql;



