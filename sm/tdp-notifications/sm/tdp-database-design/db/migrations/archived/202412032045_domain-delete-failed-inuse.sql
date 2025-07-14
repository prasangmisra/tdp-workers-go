-- function: plan_delete_domain_provision()
-- description: deletes a domain based on the plan
CREATE OR REPLACE FUNCTION plan_delete_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_domain RECORD;
    v_pd_id         UUID;
BEGIN
    SELECT * INTO v_delete_domain
    FROM v_order_delete_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain_delete(
                                            domain_id,
                                            domain_name,
                                            accreditation_id,
                                            tenant_customer_id,
                                            order_metadata,
                                            order_item_plan_ids
            ) VALUES(
                        v_delete_domain.domain_id,
                        v_delete_domain.domain_name,
                        v_delete_domain.accreditation_id,
                        v_delete_domain.tenant_customer_id,
                        v_delete_domain.order_metadata,
                        ARRAY[NEW.id]
                    ) RETURNING id
    ) SELECT id INTO v_pd_id FROM pd_ins;

    -- Validate if any of the subordinated hosts belong to customer and associated with active domains in database
    IF EXISTS (
        SELECT 1
        FROM host h
                 JOIN domain_host dh ON dh.host_id = h.id
        WHERE h.name = ANY(v_delete_domain.hosts)
    ) THEN
        UPDATE delete_domain_plan
        SET result_message = 'Host(s) are associated with active domain(s)',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;
        RETURN NEW;
    END IF;

    --  insert hosts
    IF v_delete_domain.hosts IS NOT NULL THEN
        INSERT INTO provision_domain_delete_host(
            provision_domain_delete_id,
            host_name,
            tenant_customer_id,
            order_metadata
        )
        SELECT v_pd_id, UNNEST(v_delete_domain.hosts), v_delete_domain.tenant_customer_id, v_delete_domain.order_metadata;
    END IF;

    UPDATE provision_domain_delete
    SET is_complete = TRUE
    WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
