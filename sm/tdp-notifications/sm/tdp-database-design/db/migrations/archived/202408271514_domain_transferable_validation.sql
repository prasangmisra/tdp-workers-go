-- insert new job types for transfer processing
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
    'validate_domain_transferable',
    'Validates domain is transferable',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
)
ON CONFLICT DO NOTHING;


UPDATE order_item_strategy
SET is_validation_required = TRUE
WHERE order_type_id = (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_in')
AND object_id = tc_id_from_name('order_item_object','domain')
AND provision_order = 1;


-- function: validate_transfer_domain_plan()
-- description: validates plan items for domain transfer
CREATE OR REPLACE FUNCTION validate_transfer_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data          JSONB;
    v_transfer_domain   RECORD;
BEGIN

    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_transfer_domain
    FROM v_order_transfer_in_domain votid
             JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
    WHERE votid.order_item_id = NEW.order_item_id;

--     v_transfer_domain.
    v_job_data := jsonb_build_object(
            'domain_name', v_transfer_domain.domain_name,
            'order_item_plan_id', NEW.id,
            'accreditation', v_transfer_domain.accreditation,
            'tenant_customer_id', v_transfer_domain.tenant_customer_id,
            'order_metadata', v_transfer_domain.order_metadata
                  );

    PERFORM job_submit(
            v_transfer_domain.tenant_customer_id,
            'validate_domain_transferable',
            NEW.id,
            v_job_data
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER validate_transfer_domain_plan_tg
    AFTER INSERT ON transfer_in_domain_plan
    FOR EACH ROW WHEN (
    NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
        AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_transfer_domain_plan();
