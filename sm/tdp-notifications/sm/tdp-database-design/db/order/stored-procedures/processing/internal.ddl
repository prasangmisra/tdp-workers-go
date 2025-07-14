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
