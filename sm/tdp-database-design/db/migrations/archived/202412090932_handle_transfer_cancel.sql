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
        -- fail order if client cancelled
        IF _transfer_status_name = 'clientCancelled' THEN
            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;
            RETURN NEW;
        END IF;

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
