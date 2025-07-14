INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
)
VALUES
(
    'provision_domain_transfer_away',
    'Submits domain transfer away action to the backend',
    'provision_domain_transfer_away',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
)
ON CONFLICT DO NOTHING;


INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_away'),
    tc_id_from_name('order_item_object','domain'),
    2
);


DROP TRIGGER IF EXISTS b_order_item_plan_start_tg ON order_item_transfer_away_domain;
-- starts the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
        AND NEW.transfer_status_id <> tc_id_from_name('transfer_status','pending')
    ) EXECUTE PROCEDURE order_item_plan_start();


CREATE OR REPLACE VIEW v_domain_order_item AS
SELECT
    oicd.id AS order_item_id,
    oicd.order_id,
    oicd.name AS domain_name,
    oicd.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_create_domain oicd
        JOIN order_item_status ois ON oicd.status_id = ois.id
        JOIN "order" o ON o.id = oicd.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oiud.id AS order_item_id,
    oiud.order_id,
    oiud.name AS domain_name,
    oiud.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_update_domain oiud
        JOIN order_item_status ois ON oiud.status_id = ois.id
        JOIN "order" o ON o.id = oiud.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oird.id AS order_item_id,
    oird.order_id,
    oird.name AS domain_name,
    oird.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_redeem_domain oird
        JOIN order_item_status ois ON oird.status_id = ois.id
        JOIN "order" o ON o.id = oird.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oidd.id AS order_item_id,
    oidd.order_id,
    oidd.name AS domain_name,
    oidd.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_delete_domain oidd
        JOIN order_item_status ois ON oidd.status_id = ois.id
        JOIN "order" o ON o.id = oidd.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oird.id AS order_item_id,
    oird.order_id,
    oird.name AS domain_name,
    oird.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_renew_domain oird
        JOIN order_item_status ois ON oird.status_id = ois.id
        JOIN "order" o ON o.id = oird.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oitid.id AS order_item_id,
    oitid.order_id,
    oitid.name AS domain_name,
    oitid.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_transfer_in_domain oitid
        JOIN order_item_status ois ON oitid.status_id = ois.id
        JOIN "order" o ON o.id = oitid.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oitad.id AS order_item_id,
    oitad.order_id,
    oitad.name AS domain_name,
    oitad.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_transfer_away_domain oitad
        JOIN order_item_status ois ON oitad.status_id = ois.id
        JOIN "order" o ON o.id = oitad.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id
;


-- function: plan_transfer_away_domain_provision()
-- description: responsible for creation of transfer in request and finalizing domain transfer
CREATE OR REPLACE FUNCTION plan_transfer_away_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_away_domain          RECORD;
    _transfer_status_name           TEXT;
    _provision_id                   UUID;
    _transfer_status                RECORD;
BEGIN
    SELECT * INTO v_transfer_away_domain
    FROM v_order_transfer_away_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT tc_name_from_id('transfer_status', v_transfer_away_domain.transfer_status_id)
    INTO _transfer_status_name;

    IF NEW.provision_order = 1 THEN
        INSERT INTO provision_domain_transfer_away(
            domain_id,
            domain_name,
            pw,
            transfer_status_id,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
                    v_transfer_away_domain.domain_id,
                    v_transfer_away_domain.domain_name,
                    v_transfer_away_domain.auth_info,
                    v_transfer_away_domain.transfer_status_id,
                    v_transfer_away_domain.accreditation_id,
                    v_transfer_away_domain.accreditation_tld_id,
                    v_transfer_away_domain.tenant_customer_id,
                    v_transfer_away_domain.order_metadata,
                    ARRAY[NEW.id]
                ) RETURNING id INTO _provision_id;

        IF _transfer_status_name = 'serverApproved' THEN

            UPDATE provision_domain_transfer_away
            SET status_id = tc_id_from_name('provision_status', 'completed')
            WHERE id = _provision_id;
        END IF;
    ELSIF NEW.provision_order = 2 THEN
        SELECT * INTO _transfer_status FROM transfer_status WHERE id = v_transfer_away_domain.transfer_status_id;

        IF _transfer_status.is_success THEN
            -- fail all related order items
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE order_item_id IN (
                SELECT order_item_id
                FROM v_domain_order_item
                WHERE domain_name = v_transfer_away_domain.domain_name
                  AND NOT order_status_is_final
                  AND order_item_id <> NEW.order_item_id
                  AND tenant_customer_id = v_transfer_away_domain.tenant_customer_id
            );

            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','completed')
            WHERE id = NEW.id;
        ELSE
            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER plan_transfer_away_domain_provision_tg
    AFTER UPDATE ON transfer_away_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
    EXECUTE PROCEDURE plan_transfer_away_domain_provision ();


-- function: provision_domain_transfer_away_job()
-- description: creates the job to submit transfer away action for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_away_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_away   RECORD;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_away_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.order_metadata AS metadata,
        ts.name AS transfer_status
    INTO v_transfer_away
    FROM provision_domain_transfer_away pdt
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN transfer_status ts ON ts.id = NEW.transfer_status_id
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_away SET job_id=job_submit(
        v_transfer_away.tenant_customer_id,
        'provision_domain_transfer_away',
        NEW.id,
        TO_JSONB(v_transfer_away.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_away_success()
-- description: delete the domain and provision domain record when the transfer away is successful
CREATE OR REPLACE FUNCTION provision_domain_transfer_away_success() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM domain
    WHERE id = NEW.domain_id;

    DELETE FROM provision_domain
    WHERE domain_name = NEW.domain_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TABLE provision_domain_transfer_away (
    domain_id               UUID REFERENCES domain ON DELETE CASCADE,
    domain_name             FQDN NOT NULL,
    pw                      TEXT,
    transfer_status_id      UUID NOT NULL REFERENCES transfer_status,
    accreditation_id        UUID NOT NULL REFERENCES accreditation,
    accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
    FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
    PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);


-- starts the domain transfer away provision
CREATE TRIGGER provision_domain_transfer_away_job_tg
    AFTER INSERT ON provision_domain_transfer_away
    FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
        AND NEW.transfer_status_id IN (tc_id_from_name('transfer_status','clientRejected'),
                                       tc_id_from_name('transfer_status','clientApproved'))
    ) EXECUTE PROCEDURE provision_domain_transfer_away_job();

-- trigger when the operation is successful
CREATE TRIGGER provision_domain_transfer_away_success_tg
    AFTER UPDATE ON provision_domain_transfer_away
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('provision_status','completed')
        AND NEW.transfer_status_id IN (tc_id_from_name('transfer_status','serverApproved'),
                                       tc_id_from_name('transfer_status','clientApproved'))
    ) EXECUTE PROCEDURE provision_domain_transfer_away_success();

\i triggers.ddl
\i provisioning/triggers.ddl
