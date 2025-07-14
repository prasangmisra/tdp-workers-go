DROP VIEW IF EXISTS v_order_create_domain,v_order_update_domain;
CREATE OR REPLACE VIEW v_order_update_domain AS
SELECT
    ud.id AS order_item_id,
    ud.order_id AS order_id,
    ud.accreditation_tld_id,
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
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    d.name AS domain_name,
    d.id AS domain_id,
    ud.auth_info,
    ud.hosts,
    ud.auto_renew,
    ud.locks
FROM order_item_update_domain ud
         JOIN "order" o ON o.id=ud.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
         JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;
CREATE OR REPLACE VIEW v_order_create_domain AS
SELECT
    cd.id AS order_item_id,
    cd.order_id AS order_id,
    cd.accreditation_tld_id,
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
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    cd.name AS domain_name,
    cd.registration_period AS registration_period,
    cd.auto_renew,
    cd.locks
FROM order_item_create_domain cd
         JOIN "order" o ON o.id=cd.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id
;

-- is_jsonb_empty_or_null(input_jsonb jsonb)
--       This function returns a boolean indicating whether the input JSONB is either null or an empty JSONB object.
--
CREATE OR REPLACE FUNCTION is_jsonb_empty_or_null(input_jsonb jsonb)
    RETURNS BOOLEAN AS $$
BEGIN
    RETURN input_jsonb IS NULL OR input_jsonb = '{}'::jsonb;
END;
$$ LANGUAGE plpgsql;


--------------------- Order----------------------------------------
DROP TRIGGER IF EXISTS plan_update_domain_provision_domain_tg ON update_domain_plan;
DROP FUNCTION IF EXISTS plan_update_domain_provision_domain;
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pd_id                     UUID;
BEGIN

    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pd_ins AS (
        INSERT INTO provision_domain_update(
                                            domain_id,
                                            domain_name,
                                            auth_info,
                                            hosts,
                                            accreditation_id,
                                            accreditation_tld_id,
                                            tenant_customer_id,
                                            auto_renew,
                                            order_metadata,
                                            order_item_plan_ids,
                                            locks
            ) VALUES(
                        v_update_domain.domain_id,
                        v_update_domain.domain_name,
                        v_update_domain.auth_info,
                        v_update_domain.hosts,
                        v_update_domain.accreditation_id,
                        v_update_domain.accreditation_tld_id,
                        v_update_domain.tenant_customer_id,
                        v_update_domain.auto_renew,
                        v_update_domain.order_metadata,
                        ARRAY[NEW.id],
                        v_update_domain.locks
                    ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )
        (
            SELECT
                v_pd_id,
                order_contact_id,
                domain_contact_type_id
            FROM update_domain_contact
            WHERE update_domain_id = NEW.order_item_id
        );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pd_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER plan_update_domain_provision_domain_tg
    AFTER UPDATE ON update_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
EXECUTE PROCEDURE plan_update_domain_provision_domain();

DROP TRIGGER IF EXISTS plan_create_domain_provision_domain_tg ON create_domain_plan;
DROP FUNCTION IF EXISTS plan_create_domain_provision_domain;
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_domain          RECORD;
    v_create_domain   RECORD;
    v_pd_id           UUID;
    v_parent_id       UUID;
    v_locks_required_changes jsonb;
    v_order_item_plan_ids UUID[];
BEGIN

    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain(
                                     domain_name,
                                     registration_period,
                                     accreditation_id,
                                     accreditation_tld_id,
                                     tenant_customer_id,
                                     auto_renew,
                                     order_metadata
            ) VALUES(
                        v_create_domain.domain_name,
                        v_create_domain.registration_period,
                        v_create_domain.accreditation_id,
                        v_create_domain.accreditation_tld_id,
                        v_create_domain.tenant_customer_id,
                        v_create_domain.auto_renew,
                        v_create_domain.order_metadata
                    ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    SELECT
        jsonb_object_agg(key, value)
    INTO v_locks_required_changes FROM jsonb_each(v_create_domain.locks) WHERE value::BOOLEAN = TRUE;

    IF NOT is_jsonb_empty_or_null(v_locks_required_changes) THEN
        WITH inserted_domain_update AS (
            INSERT INTO provision_domain_update(
                                                domain_name,
                                                accreditation_id,
                                                accreditation_tld_id,
                                                tenant_customer_id,
                                                order_metadata,
                                                order_item_plan_ids,
                                                locks
                )
                VALUES (
                           v_create_domain.domain_name,
                           v_create_domain.accreditation_id,
                           v_create_domain.accreditation_tld_id,
                           v_create_domain.tenant_customer_id,
                           v_create_domain.order_metadata,
                           ARRAY[NEW.id],
                           v_locks_required_changes
                       )
                RETURNING id
        )

        SELECT id INTO v_parent_id FROM inserted_domain_update;
    ELSE
        v_order_item_plan_ids := ARRAY [NEW.id];
    end if;

    -- we now signal the provisioning


    -- insert contacts
    INSERT INTO provision_domain_contact(
        provision_domain_id,
        contact_id,
        contact_type_id
    )
        ( SELECT
              v_pd_id,
              order_contact_id,
              domain_contact_type_id
          FROM create_domain_contact
          WHERE create_domain_id = NEW.order_item_id
        );

    -- insert hosts
    INSERT INTO provision_domain_host(
        provision_domain_id,
        host_id
    ) (
        SELECT
            v_pd_id,
            h.id
        FROM ONLY host h
                 JOIN order_host oh ON oh.name = h.name
                 JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
        WHERE cdn.create_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
    );

    UPDATE provision_domain SET is_complete = TRUE,
                                order_item_plan_ids = v_order_item_plan_ids,
                                parent_id = v_parent_id
    WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER plan_create_domain_provision_domain_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
EXECUTE PROCEDURE plan_create_domain_provision_domain();

--------------------- provision ----------------------------------------
ALTER TABLE provision_domain ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES provision_domain_update ON DELETE CASCADE;
ALTER TABLE provision_domain_update ADD COLUMN IF NOT EXISTS locks JSONB;


DROP TRIGGER IF EXISTS provision_domain_update_job_tg ON provision_domain_update;
--
-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
DROP FUNCTION IF EXISTS provision_domain_update_job;
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
                 JOIN domain_contact_type ct ON ct.id =  pdc.contact_type_id
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
                 JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
          AND pdc.provision_domain_update_id = NEW.id
    ), hosts AS(
        SELECT JSONB_AGG(data) AS data
        FROM(
                SELECT
                    JSON_BUILD_OBJECT(
                            'name', h.name,
                            'ip_addresses', JSONB_AGG(ha.address)
                    ) AS data
                FROM host h
                         JOIN host_addr ha ON h.id = ha.host_id
                WHERE h.name IN (SELECT UNNEST(NEW.hosts))
                GROUP BY h.name
            ) sub_q
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.order_metadata,
        d.domain_name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        hosts.data as nameservers,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS order_metadata,
        va1.value::BOOL AS is_rem_update_lock_with_domain_content_supported,
        va2.value::BOOL AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
             LEFT JOIN contacts ON TRUE
             LEFT JOIN hosts ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
             JOIN v_attribute va1 ON
        va1.tld_id = vat.tld_id AND
        va1.key = 'tld.order.is_rem_update_lock_with_domain_content_supported' AND
        va1.tenant_id = tnc.tenant_id
             JOIN v_attribute va2 ON
        va2.tld_id = vat.tld_id AND
        va2.key = 'tld.order.is_add_update_lock_with_domain_content_supported' AND
        va2.tenant_id = tnc.tenant_id
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
        IF (v_locks_required_changes->'update')::boolean IS FALSE AND
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
                                       'accreditation',v_domain.accreditation),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN

        -- Same thing here, if 'update' lock has true value (add the lock) and the registry DOES NOT support adding that
        -- lock with the other domain changes in a single command, then we need to create two jobs: the first one to
        -- handle the other domain changes and the second one to add the domain lock

        elsif (v_locks_required_changes->'update')::boolean IS TRUE AND
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

CREATE OR REPLACE TRIGGER provision_domain_update_job_tg
    AFTER UPDATE ON provision_domain_update
    FOR EACH ROW WHEN (OLD.is_complete <> NEW.is_complete AND NEW.is_complete)
EXECUTE PROCEDURE provision_domain_update_job();

DROP TRIGGER IF EXISTS provision_domain_update_success_tg ON provision_domain_update;

--
-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
DROP FUNCTION IF EXISTS provision_domain_update_success;
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    _key   text;
    _value BOOLEAN;
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
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM
        domain_host dh
        USING
            host h
    WHERE
        NEW.hosts IS NOT NULL
      AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
      AND dh.domain_id = NEW.domain_id
      AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info)
    WHERE d.id = NEW.domain_id;

    IF NEW.locks IS NOT NULL THEN
        FOR _key, _value IN SELECT * FROM jsonb_each_text(NEW.locks)
            LOOP
                IF _value THEN
                    INSERT INTO domain_lock(domain_id,type_id) VALUES
                        (NEW.domain_id,(SELECT id FROM lock_type where name=_key)) ON CONFLICT DO NOTHING ;

                ELSE
                    DELETE FROM domain_lock WHERE domain_id=NEW.domain_id AND
                        type_id=tc_id_from_name('lock_type',_key);
                end if;
            end loop;
    end if;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER provision_domain_update_success_tg
    AFTER UPDATE ON provision_domain_update
    FOR EACH ROW WHEN (
    NEW.is_complete
        AND OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('provision_status','completed')
) EXECUTE PROCEDURE provision_domain_update_success();





DROP TRIGGER IF EXISTS provision_domain_success_tg ON provision_domain;
DROP TRIGGER IF EXISTS provision_domain_status_update_tg ON provision_domain;
DROP FUNCTION IF EXISTS provision_domain_success;

CREATE OR REPLACE FUNCTION provision_domain_status_update() RETURNS TRIGGER AS $$
DECLARE
    v_domain_create_status     TEXT;
BEGIN
    SELECT
        ps.name
    INTO
        v_domain_create_status
    FROM provision_status ps WHERE  ps.id = NEW.status_id;

    CASE
        WHEN v_domain_create_status = 'completed' THEN

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
                auto_renew
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
                    pd.auto_renew
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
                         JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
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

            -- start the provision domain update
            IF NEW.parent_id IS NOT NULL THEN
                UPDATE provision_domain_update SET
                                                   is_complete = TRUE,
                                                   domain_id = NEW.id
                WHERE id = NEW.parent_id;
            end if;

        WHEN v_domain_create_status = 'failed' THEN
            -- fail the provision domain update
            IF NEW.parent_id IS NOT NULL THEN
                UPDATE provision_domain_update SET status_id = NEW.status_id WHERE id = NEW.parent_id;
            END IF;
        END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER provision_domain_status_update_tg
    AFTER UPDATE ON provision_domain
    FOR EACH ROW WHEN (
    NEW.is_complete
        AND OLD.status_id <> NEW.status_id
) EXECUTE PROCEDURE provision_domain_status_update();

INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
    (
        'is_rem_update_lock_with_domain_content_supported',
        (SELECT id FROM attr_category WHERE name='order'),
        'Registry supports updating the domain and removing the domain update lock with a single command.',
        (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
        FALSE::TEXT,
        TRUE
    ),
    (
        'is_add_update_lock_with_domain_content_supported',
        (SELECT id FROM attr_category WHERE name='order'),
        'Registry supports updating the domain and adding the domain update lock with a single command.',
        (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
        TRUE::TEXT,
        TRUE
    );

DROP VIEW IF EXISTS v_domain;
CREATE OR REPLACE VIEW v_domain AS
SELECT
    d.*,
    rgp.id AS rgp_status_id,
    rgp.epp_name AS rgp_epp_status,
    lock.names AS locks
FROM domain d
         LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.id,
        drs.expiry_date
    FROM domain_rgp_status drs
             JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
    ) rgp ON rgp.expiry_date >= NOW()
         LEFT JOIN LATERAL (
    SELECT
        JSON_AGG(vdl.name) AS names
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = d.id AND NOT vdl.is_internal
    ) lock ON TRUE;

