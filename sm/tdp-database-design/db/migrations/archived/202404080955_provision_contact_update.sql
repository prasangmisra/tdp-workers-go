-- update job_type records
UPDATE job_type
SET reference_table = 'provision_domain_contact_update'
WHERE NAME = 'provision_domain_contact_update';

UPDATE job_type
SET reference_table = 'provision_contact_update'
WHERE NAME = 'provision_contact_update';

-- contact functions

--
-- function: update_contact_using_order_contact()
-- description: updates contact and details using order contact
--

CREATE OR REPLACE FUNCTION update_contact_using_order_contact(c_id UUID, oc_id UUID) RETURNS void AS $$
BEGIN
    -- update contact
    UPDATE
        contact c
    SET
        type_id = oc.type_id,
        title = oc.title,
        org_reg = oc.org_reg,
        org_vat = oc.org_vat,
        org_duns = oc.org_duns,
        email = oc.email,
        phone = oc.phone,
        fax = oc.fax,
        country = oc.country,
        language = oc.language,
        customer_contact_ref = oc.customer_contact_ref,
        tags = oc.tags,
        documentation = oc.documentation
    FROM
        order_contact oc
    WHERE
        c.id = c_id AND oc.id = oc_id;

    -- update contact_postal
    UPDATE
        contact_postal cp
    SET
        is_international=ocp.is_international,
        first_name=ocp.first_name,
        last_name=ocp.last_name,
        org_name=ocp.org_name,
        address1=ocp.address1,
        address2=ocp.address2,
        address3=ocp.address3,
        city=ocp.city,
        postal_code=ocp.postal_code,
        state=ocp.state
    FROM
        order_contact_postal ocp
    WHERE
        ocp.contact_id = oc_id AND
        cp.contact_id = c_id AND
        cp.is_international = ocp.is_international;

    -- update contact_attribute
    UPDATE
        contact_attribute ca
    SET
        value=oca.value
    FROM order_contact_attribute oca
    WHERE
        oca.contact_id = oc_id AND
        ca.contact_id = c_id AND
        ca.attribute_id = oca.attribute_id AND
        ca.attribute_type_id = oca.attribute_type_id;

END;
$$ LANGUAGE plpgsql;


--
-- function: duplicate_contact_by_id()
-- description: create new contact and details from existing contact
--
CREATE OR REPLACE FUNCTION duplicate_contact_by_id(c_id UUID) RETURNS UUID AS $$
DECLARE
    _contact_id     UUID;
BEGIN
    -- create new contact
    WITH c_id AS (
        INSERT INTO contact(
                            type_id,
                            title,
                            org_reg,
                            org_vat,
                            org_duns,
                            tenant_customer_id,
                            email,
                            phone,
                            fax,
                            country,
                            "language",
                            customer_contact_ref,
                            tags,
                            documentation
            )
            SELECT
                type_id,
                title,
                org_reg,
                org_vat,
                org_duns,
                tenant_customer_id,
                email,
                phone,
                fax,
                country,
                "language",
                customer_contact_ref,
                tags,
                documentation
            FROM
                ONLY contact
            WHERE
                id = c_id
            RETURNING
                id
    )
    SELECT
        * INTO _contact_id
    FROM
        c_id;

    INSERT INTO contact_postal(
        contact_id,
        is_international,
        first_name,
        last_name,
        org_name,
        address1,
        address2,
        address3,
        city,
        postal_code,
        state
    )
    SELECT
        _contact_id,
        is_international,
        first_name,
        last_name,
        org_name,
        address1,
        address2,
        address3,
        city,
        postal_code,
        state
    FROM
        ONLY contact_postal
    WHERE
        contact_id = c_id;

    INSERT INTO contact_attribute(contact_id, attribute_id, attribute_type_id, value)
    SELECT
        _contact_id,
        attribute_id,
        attribute_type_id,
        value
    FROM
        ONLY contact_attribute
    WHERE
        contact_id = c_id;

    RETURN _contact_id;

END;
$$ LANGUAGE plpgsql;

-- update view
DROP VIEW IF EXISTS v_order_update_contact;
CREATE OR REPLACE VIEW v_order_update_contact AS
SELECT
    uc.id AS order_item_id,
    uc.order_id AS order_id,
    uc.contact_id AS contact_id,
    uc.new_contact_id AS new_contact_id,
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
         JOIN order_contact oc ON oc.id = uc.new_contact_id
         JOIN contact_type ct ON ct.id = oc.type_id
         LEFT JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
         JOIN "order" o ON o.id=uc.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
;

-- insert order_item_strategy
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
VALUES(
    (SELECT type_id FROM v_order_product_type WHERE product_name='contact' AND type_name='update'),
    tc_id_from_name('order_item_object','contact'),
    1
);

-- provision tables
CREATE TABLE IF NOT EXISTS provision_contact_update (
    order_metadata            JSONB,
    contact_id                UUID NOT NULL REFERENCES contact,
    new_contact_id            UUID NOT NULL REFERENCES order_contact,
    is_complete               BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id),
    FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

--
-- table: provision_domain_contact_update
-- description: This table is for provisioning a domain contact update in the backend. It does not inherit from the
-- class.provision to prevent the cleanup of failed provisions resulting from partially successful updates.
--
CREATE TABLE IF NOT EXISTS provision_domain_contact_update(
    id                              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    provision_contact_update_id     UUID NOT NULL REFERENCES provision_contact_update
        ON DELETE CASCADE,
    contact_id                      UUID NOT NULL REFERENCES contact,
    new_contact_id                  UUID NOT NULL REFERENCES order_contact,
    accreditation_id                UUID NOT NULL REFERENCES accreditation,
    handle                          TEXT,
    tenant_customer_id              UUID NOT NULL REFERENCES tenant_customer,
    status_id                       UUID NOT NULL DEFAULT tc_id_from_name('provision_status','pending'),
    job_id                          UUID REFERENCES job,
    UNIQUE(provision_contact_update_id,handle)
) INHERITS(class.audit_trail);


-- add plan flow
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
           va1.value::BOOL AS is_owner_contact_change_supported,
           va2.value::BOOL AS is_contact_update_supported
    FROM domain_contact dc
    JOIN domain d ON d.id = dc.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN v_attribute va1 ON
        va1.tld_id = vat.tld_id AND
        va1.key = 'tld.contact.is_owner_contact_change_supported' AND
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
        IF (_contact.type = 'registrant' AND NOT _contact.is_owner_contact_change_supported) OR NOT _contact.is_contact_update_supported THEN
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

-- provision triggers

-- function: provision_contact_update_job()
-- description: creates contact update parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_update_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_job         RECORD;
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
        WHERE c.id=_child_job.new_contact_id;

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
    PERFORM update_contact_using_order_contact(NEW.contact_id, NEW.new_contact_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- triggers
CREATE OR REPLACE TRIGGER provision_contact_update_job_tg
    AFTER UPDATE ON provision_contact_update
    FOR EACH ROW WHEN (OLD.is_complete <> NEW.is_complete AND NEW.is_complete)
    EXECUTE PROCEDURE provision_contact_update_job();

CREATE OR REPLACE TRIGGER provision_contact_update_success_tg
    AFTER UPDATE ON provision_contact_update
    FOR EACH ROW WHEN (
    NEW.is_complete
        AND OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('provision_status','completed')
    ) EXECUTE PROCEDURE provision_contact_update_success();

--
-- function: jsonb_get_order_contact_by_id()
-- description: returns a jsonb containing all the attributes of an order contact
--

CREATE OR REPLACE FUNCTION jsonb_get_order_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                     SELECT id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, customer_contact_ref, tags, documentation
                     FROM ONLY order_contact WHERE
                         id = p_id
                 ) c
        )
            ||
        COALESCE(
                ( -- The additional attributes of a contact, from the contact_attribute table
                    SELECT jsonb_object_agg(an.name, ca.value) AS extended_attr
                    FROM ONLY order_contact_attribute ca
                             JOIN attribute an ON an.id=ca.attribute_id
                    WHERE ca.contact_id = p_id
                    GROUP BY ca.contact_id
                )
            , '{}'::JSONB)
            ||
        ( -- The postal info of a contact as an object holding the array sorting the UTF-8 representation before the ASCII-only representation
            SELECT to_jsonb(cpa)
            FROM (
                     SELECT jsonb_agg(cp) AS contact_postals
                     FROM (
                              SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                              FROM ONLY order_contact_postal
                              WHERE contact_id = p_id
                              ORDER BY is_international ASC
                          ) cp
                 ) cpa
        );
END;
$$ LANGUAGE plpgsql STABLE;

\i triggers.ddl
\i provisioning/triggers.ddl

