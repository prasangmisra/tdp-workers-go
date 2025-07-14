-- table: update_domain_add_contact
-- description: this table stores attributes of contact to be added to domain.
--
CREATE TABLE IF NOT EXISTS update_domain_add_contact (
   update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
   order_contact_id              UUID NOT NULL REFERENCES order_contact,
   domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
   short_id                TEXT,
   PRIMARY KEY(update_domain_id,order_contact_id, domain_contact_type_id)
) INHERITS(class.audit);


CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_add_contact
    FOR EACH ROW WHEN (
    NEW.order_contact_id IS NULL AND
    NEW.short_id IS NOT NULL
    )
EXECUTE PROCEDURE set_order_contact_id_from_short_id();

--
-- table: update_domain_rem_contact
-- description: this table stores attributes of contact to be removed from domain.
--
CREATE TABLE IF NOT EXISTS update_domain_rem_contact (
   update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
   order_contact_id              UUID NOT NULL REFERENCES order_contact,
   domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
   short_id                TEXT,
   PRIMARY KEY(update_domain_id,order_contact_id, domain_contact_type_id)
) INHERITS(class.audit);

DROP TRIGGER IF EXISTS order_prevent_if_update_domain_contact_does_not_exist_tg ON update_domain_add_contact;
CREATE OR REPLACE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_add_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();

DROP TRIGGER IF EXISTS order_prevent_if_update_domain_contact_does_not_exist_tg ON update_domain_rem_contact;
CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_rem_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();


CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_rem_contact
    FOR EACH ROW WHEN (
    NEW.order_contact_id IS NULL AND
    NEW.short_id IS NOT NULL
    )
EXECUTE PROCEDURE set_order_contact_id_from_short_id();


CREATE OR REPLACE VIEW v_order_item_plan_object AS
SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    distinct_order_contact.id AS id
FROM order_item_create_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'contact'
         JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact
    WHERE create_domain_id = d.id
    ) AS distinct_order_contact ON TRUE

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    distinct_order_host.id AS id
FROM order_item_create_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'host'
         JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM create_domain_nameserver
    WHERE create_domain_id = d.id
    ) AS distinct_order_host ON TRUE

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_create_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_renew_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id AS object_id,
    d.id AS id
FROM order_item_redeem_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj on obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_delete_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_transfer_in_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_transfer_away_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    distinct_order_host.id AS id
FROM order_item_update_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'host'
         JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM update_domain_add_nameserver
    WHERE update_domain_id = d.id
    ) AS distinct_order_host ON TRUE

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    distinct_order_contact.id AS id
FROM order_item_update_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'contact'
         JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_contact
    WHERE update_domain_id = d.id

    UNION ALL

    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_add_contact
    WHERE update_domain_id = d.id
    ) AS distinct_order_contact ON TRUE

UNION

SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
FROM order_item_update_domain d
         JOIN "order" o ON o.id = d.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_create_contact c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_create_hosting c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_create_hosting c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'hosting_certificate'

UNION


SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_delete_hosting c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_update_hosting c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
    h.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    h.id AS id
FROM order_item_create_host h
         JOIN "order" o ON o.id = h.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_update_contact c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
FROM order_item_delete_contact c
         JOIN "order" o ON o.id = c.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
    h.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    h.id AS id
FROM order_item_update_host h
         JOIN "order" o ON o.id = h.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
    h.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    h.id AS id
FROM order_item_delete_host h
         JOIN "order" o ON o.id = h.order_id
         JOIN order_type ot ON ot.id = o.type_id
         JOIN product p ON p.id = ot.product_id
         JOIN order_item_object obj ON obj.name = 'host'
;

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

    -- Check if trying to add a contact type that already exists and is not being removed
    IF EXISTS (
        SELECT 1
        FROM update_domain_add_contact udac
                 JOIN domain_contact dc ON dc.domain_id = v_update_domain.domain_id
            AND dc.domain_contact_type_id = udac.domain_contact_type_id
        WHERE udac.update_domain_id = NEW.order_item_id
          AND udac.order_contact_id = NEW.reference_id
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
            domain_contact_type_id,
            v_update_domain.accreditation_tld_id
                   )) INTO _supported_contact_type
    FROM (
             -- Combine rows from both tables, as the contact can be in either table
             SELECT domain_contact_type_id
             FROM update_domain_contact
             WHERE order_contact_id = NEW.reference_id
               AND update_domain_id = NEW.order_item_id

             UNION ALL

             SELECT domain_contact_type_id
             FROM update_domain_add_contact
             WHERE order_contact_id = NEW.reference_id
               AND update_domain_id = NEW.order_item_id
         ) AS combined_contacts;

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


-- function: plan_update_domain_provision_domain()
-- description: update a domain based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pdu_id                     UUID;
BEGIN
    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pdu_ins AS (
        INSERT INTO provision_domain_update(
                                            domain_id,
                                            domain_name,
                                            auth_info,
                                            accreditation_id,
                                            accreditation_tld_id,
                                            tenant_customer_id,
                                            auto_renew,
                                            order_metadata,
                                            order_item_plan_ids,
                                            locks,
                                            secdns_max_sig_life
            ) VALUES(
                        v_update_domain.domain_id,
                        v_update_domain.domain_name,
                        v_update_domain.auth_info,
                        v_update_domain.accreditation_id,
                        v_update_domain.accreditation_tld_id,
                        v_update_domain.tenant_customer_id,
                        v_update_domain.auto_renew,
                        v_update_domain.order_metadata,
                        ARRAY[NEW.id],
                        v_update_domain.locks,
                        v_update_domain.secdns_max_sig_life
                    ) RETURNING id
    )
    SELECT id INTO v_pdu_id FROM pdu_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    INSERT INTO provision_domain_update_add_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_add_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    INSERT INTO provision_domain_update_rem_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_rem_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    -- insert hosts to add
    INSERT INTO provision_domain_update_add_host(
        provision_domain_update_id,
        host_id
    ) (
        SELECT
            v_pdu_id,
            h.id
        FROM ONLY host h
                 JOIN order_host oh ON oh.name = h.name
                 JOIN update_domain_add_nameserver udan ON udan.host_id = oh.id
        WHERE udan.update_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
    );

    -- insert hosts to remove
    INSERT INTO provision_domain_update_rem_host(
        provision_domain_update_id,
        host_id
    ) (
        SELECT
            v_pdu_id,
            h.id
        FROM ONLY host h
                 JOIN order_host oh ON oh.name = h.name
                 JOIN update_domain_rem_nameserver udrn ON udrn.host_id = oh.id
                 JOIN domain_host dh ON dh.host_id = h.id
        WHERE udrn.update_domain_id = NEW.order_item_id
          AND oh.tenant_customer_id = h.tenant_customer_id
          -- make sure host to be removed is associated with domain
          AND dh.domain_id = v_update_domain.domain_id
    );

    -- insert secdns to add
    INSERT INTO provision_domain_update_add_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pdu_id,
            id
        FROM update_domain_add_secdns
        WHERE update_domain_id = NEW.order_item_id
    );

    -- insert hosts to remove
    INSERT INTO provision_domain_update_rem_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pdu_id,
            id
        FROM update_domain_rem_secdns
        WHERE update_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pdu_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


------------------------------------------------------------------------------------------------------------------------

--
-- table: provision_domain_update_add_contact
-- description: this table is to add domain contact association in a backend.
--
CREATE TABLE provision_domain_update_add_contact (
 provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update
     ON DELETE CASCADE,
 contact_id                        UUID NOT NULL REFERENCES contact,
 contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
 PRIMARY KEY (provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);

--
-- table: provision_domain_update_rem_contact
-- description: this table is to remove domain contact association in a backend.
--
CREATE TABLE provision_domain_update_rem_contact (
 provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update
     ON DELETE CASCADE,
 contact_id                        UUID NOT NULL REFERENCES contact,
 contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
 PRIMARY KEY (provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);


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
    ), contacts_add AS(
        SELECT JSONB_AGG(data) AS add
        FROM (
                 SELECT
                     JSON_BUILD_OBJECT(
                             'type', ct.name,
                             'handle', pc.handle
                     ) AS data
                 FROM provision_domain_update_add_contact pduac
                          JOIN domain_contact_type ct ON ct.id = pduac.contact_type_id
                          JOIN provision_contact pc ON pc.contact_id = pduac.contact_id
                          JOIN provision_status ps ON ps.id = pc.status_id
                 WHERE
                     ps.is_success AND ps.is_final AND pc.accreditation_id = NEW.accreditation_id
                   AND pduac.provision_domain_update_id = NEW.id
             ) sub_q
    ), contacts_rem AS(
        SELECT JSONB_AGG(data) AS rem
        FROM (
                 SELECT
                     JSON_BUILD_OBJECT(
                             'type', ct.name,
                             'handle', dc.handle
                     ) AS data
                 FROM provision_domain_update_rem_contact pdurc
                          JOIN provision_domain_update pdu ON pdu.id = pdurc.provision_domain_update_id
                          JOIN domain_contact dc on dc.domain_id = pdu.domain_id
                     AND dc.domain_contact_type_id = pdurc.contact_type_id
                     AND dc.contact_id = pdurc.contact_id
                          JOIN domain_contact_type ct ON ct.id = pdurc.contact_type_id
                 WHERE pdurc.provision_domain_update_id = NEW.id
             ) sub_q
    ),hosts_add AS(
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
        coalesce(contacts.data, TO_JSONB(contacts_add) || TO_JSONB(contacts_rem))AS contacts,
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
             LEFT JOIN contacts_add ON TRUE
             LEFT JOIN contacts_rem ON TRUE
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
    ) ON CONFLICT (domain_id, domain_contact_type_id) DO NOTHING;

    DELETE FROM domain_contact dc
        USING provision_domain_update_rem_contact pduc
    WHERE dc.domain_id = NEW.domain_id
      AND dc.contact_id = pduc.contact_id
      AND dc.domain_contact_type_id = pduc.contact_type_id
      AND pduc.provision_domain_update_id = NEW.id;

    -- if we have multiple contacts with the same type in the request, we will end up single contact for the given type
    -- this is a limitation of the current design
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
