
INSERT INTO order_type (product_id,name) SELECT id, 'create_internal' FROM product WHERE name = 'domain' ON CONFLICT DO NOTHING;
INSERT INTO order_type (product_id,name) SELECT id, 'update_internal' FROM product WHERE name = 'domain' ON CONFLICT DO NOTHING;
INSERT INTO order_type (product_id,name) SELECT id, 'delete_internal' FROM product WHERE name = 'domain' ON CONFLICT DO NOTHING;

INSERT INTO order_item_strategy(order_type_id,object_id,is_validation_required,provision_order)
VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update_internal'),
    tc_id_from_name('order_item_object','domain'),
    FALSE,
    1
);

CREATE TABLE IF NOT EXISTS  update_internal_domain_plan(
  PRIMARY KEY(id)
) INHERITS(order_item_plan, class.audit_trail);

CREATE OR REPLACE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_internal_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE OR REPLACE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_internal_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

-- function: update_domain_locks()
-- description: updates the locks for a domain
CREATE OR REPLACE FUNCTION update_domain_locks(v_domain_id UUID, v_locks JSONB) RETURNS VOID AS $$
DECLARE
    _lock   TEXT;
    _is_set BOOLEAN;
BEGIN
    FOR _lock, _is_set IN SELECT * FROM jsonb_each_text(v_locks)
    LOOP
        IF _is_set THEN
            INSERT INTO domain_lock(domain_id, type_id)
            VALUES (v_domain_id, tc_id_from_name('lock_type', _lock))
            ON CONFLICT DO NOTHING;
        ELSE
            DELETE FROM domain_lock
            WHERE domain_id = v_domain_id
            AND type_id = tc_id_from_name('lock_type', _lock);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- function: remove_domain_secdns_data()
-- description: removes secdns data for a domain
CREATE OR REPLACE FUNCTION remove_domain_secdns_data(v_domain_id UUID, v_update_domain_rem_secdns_ids UUID[]) RETURNS VOID AS $$
BEGIN
    WITH secdns_ds_data_rem AS (
        SELECT 
            ds.ds_data_id AS id,
            sdd.key_data_id AS key_data_id
        FROM update_domain_rem_secdns udrs
        -- join data in order
        JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
        LEFT JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
        -- join data in domain
        JOIN domain_secdns ds ON ds.domain_id = v_domain_id
        JOIN secdns_ds_data sdd ON sdd.id = ds.ds_data_id
        LEFT JOIN secdns_key_data skd ON skd.id = sdd.key_data_id
        WHERE udrs.id = ANY(v_update_domain_rem_secdns_ids)
            -- find matching data
            AND sdd.key_tag = osdd.key_tag
            AND sdd.algorithm = osdd.algorithm
            AND sdd.digest_type = osdd.digest_type
            AND sdd.digest = osdd.digest
            AND (
                (sdd.key_data_id IS NULL AND osdd.key_data_id IS NULL)
                OR
                (
                    skd.flags = oskd.flags
                    AND skd.protocol = oskd.protocol
                    AND skd.algorithm = oskd.algorithm
                    AND skd.public_key = oskd.public_key
                )
            )
    ),
    -- remove ds key data first if exists
    secdns_ds_key_data_rem AS (
        DELETE FROM ONLY secdns_key_data WHERE id IN (
            SELECT key_data_id FROM secdns_ds_data_rem WHERE key_data_id IS NOT NULL
        )
    )
    -- remove secdns ds data if any
    DELETE FROM ONLY secdns_ds_data WHERE id IN (SELECT id FROM secdns_ds_data_rem);

    -- remove secdns key data if any
    DELETE FROM ONLY secdns_key_data
    WHERE id IN (
        SELECT skd.id
        FROM update_domain_rem_secdns udrs
        JOIN order_secdns_key_data oskd ON oskd.id = udrs.key_data_id
        JOIN domain_secdns ds ON ds.domain_id = v_domain_id
        JOIN secdns_key_data skd ON skd.id = ds.key_data_id
        WHERE udrs.id  = ANY(v_update_domain_rem_secdns_ids)
          AND skd.flags = oskd.flags
          AND skd.protocol = oskd.protocol
          AND skd.algorithm = oskd.algorithm
          AND skd.public_key = oskd.public_key
    );

END;
$$ LANGUAGE plpgsql;


-- function: add_domain_secdns_data()
-- description: adds secdns data for a domain
CREATE OR REPLACE FUNCTION add_domain_secdns_data(v_domain_id UUID, v_update_domain_add_secdns_ids UUID[]) RETURNS VOID AS $$
BEGIN
    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM update_domain_add_secdns udas
                JOIN order_secdns_key_data oskd ON oskd.id = udas.key_data_id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM update_domain_add_secdns udas
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
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
            FROM update_domain_add_secdns udas
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT v_domain_id, NULL, id FROM key_data

        UNION ALL

        SELECT v_domain_id, id, NULL FROM ds_data
    );
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_internal_domain()
-- description: update a domain based on the internal plan in database only

CREATE OR REPLACE FUNCTION plan_update_internal_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain RECORD;
BEGIN
    -- Fetch order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Update domain details
    UPDATE domain d
    SET auto_renew = COALESCE(v_update_domain.auto_renew, d.auto_renew),
        auth_info = COALESCE(v_update_domain.auth_info, d.auth_info),
        secdns_max_sig_life = COALESCE(v_update_domain.secdns_max_sig_life, d.secdns_max_sig_life)
    WHERE d.id = v_update_domain.domain_id
      AND d.tenant_customer_id = v_update_domain.tenant_customer_id;

    -- Update domain locks if present
    IF v_update_domain.locks IS NOT NULL THEN
        PERFORM update_domain_locks(v_update_domain.domain_id, v_update_domain.locks);
    END IF;

    -- Remove secdns data
    PERFORM remove_domain_secdns_data(
        v_update_domain.domain_id,
        ARRAY(
            SELECT id
            FROM update_domain_rem_secdns
            WHERE update_domain_id = NEW.order_item_id
        )
    );

    -- Add secdns data
    PERFORM add_domain_secdns_data(
        v_update_domain.domain_id,
        ARRAY(
            SELECT id
            FROM update_domain_add_secdns
            WHERE update_domain_id = NEW.order_item_id
        )
    );

    -- Update the status of the plan
    UPDATE order_item_plan
    SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
    WHERE id = NEW.id;

    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE order_item_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER plan_update_internal_domain_tg 
  AFTER UPDATE ON update_internal_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE plan_update_internal_domain();

-- function: validate_rem_secdns_exists()
-- description: validate that the secdns record we are trying to remove exists
CREATE OR REPLACE FUNCTION validate_rem_secdns_exists() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM ONLY secdns_ds_data
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
        PERFORM 1 FROM ONLY secdns_key_data
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
        PERFORM 1 FROM ONLY secdns_ds_data 
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
        PERFORM 1 FROM ONLY secdns_key_data
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
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id AND pc.accreditation_id = NEW.accreditation_id
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
