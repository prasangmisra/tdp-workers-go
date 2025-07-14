DROP VIEW IF EXISTS v_order_transfer_in_domain;
CREATE OR REPLACE VIEW v_order_transfer_in_domain AS
SELECT
    tid.id AS order_item_id,
    tid.order_id AS order_id,
    tid.accreditation_tld_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    s.is_final AS status_is_final,
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
    tid.name AS domain_name,
    tid.transfer_period,
    tid.auth_info,
    tid.tags,
    tid.metadata,
    tid.created_date,
    tid.updated_date
FROM order_item_transfer_in_domain tid
         JOIN "order" o ON o.id=tid.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = tid.accreditation_tld_id
;


CREATE OR REPLACE FUNCTION provision_domain_transfer_in_request_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
BEGIN
    WITH
        price AS (
            SELECT
                CASE
                    WHEN voip.price IS NULL THEN NULL
                    ELSE JSONB_BUILD_OBJECT(
                            'amount', voip.price,
                            'currency', voip.currency_type_code,
                            'fraction', voip.currency_type_fraction
                         )
                    END AS data
            FROM v_order_item_price voip
                     JOIN v_order_transfer_in_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
            WHERE vord.domain_name = NEW.domain_name
            ORDER BY vord.created_date DESC
            LIMIT 1
        )

    SELECT
        NEW.id AS provision_domain_transfer_in_request_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.transfer_period,
        pdt.order_metadata AS metadata,
        price.data AS price
    INTO v_transfer_in
    FROM provision_domain_transfer_in_request pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
             LEFT JOIN price ON TRUE
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_in_request SET job_id=job_submit(
            v_transfer_in.tenant_customer_id,
            'provision_domain_transfer_in_request',
            NEW.id,
            TO_JSONB(v_transfer_in.*)
                                                           ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
