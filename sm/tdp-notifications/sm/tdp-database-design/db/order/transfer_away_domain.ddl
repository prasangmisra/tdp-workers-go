CREATE TABLE order_item_transfer_away_domain (
    domain_id               UUID NOT NULL,
    name                    FQDN NOT NULL,
    transfer_status_id      UUID NOT NULL REFERENCES transfer_status,
    requested_by            TEXT NOT NULL,
    requested_date          TIMESTAMPTZ NOT NULL,
    action_by               TEXT NOT NULL,
    action_date             TIMESTAMPTZ NOT NULL,
    expiry_date             TIMESTAMPTZ NOT NULL,
    auth_info               TEXT,
    accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
    metadata                JSONB DEFAULT '{}'::JSONB,
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
)
INHERITS (order_item, class.audit_trail);

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets accreditation_tld_id from domain name when it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL )
EXECUTE PROCEDURE order_item_set_tld_id();

-- check if domain from order data exists
CREATE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

-- check if provided auth info matches the domain auth info
CREATE TRIGGER order_prevent_if_domain_with_auth_info_does_not_exist_tg
    BEFORE UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN ( NEW.auth_info IS NOT NULL )
    EXECUTE PROCEDURE order_prevent_if_domain_with_auth_info_does_not_exist();

-- make sure the transfer auth info is valid
CREATE TRIGGER validate_auth_info_tg
    BEFORE UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('transfer_away');

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_transfer_away_plan_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
        NEW.status_id = tc_id_from_name('order_item_status','ready')
        AND NEW.transfer_status_id <> tc_id_from_name('transfer_status','pending')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE TRIGGER event_domain_transfer_away_order_tg
    AFTER INSERT OR UPDATE OF transfer_status_id ON order_item_transfer_away_domain
    FOR EACH ROW
    WHEN (NEW.transfer_status_id IS NOT NULL)
EXECUTE PROCEDURE event_domain_transfer_away_order();

CREATE INDEX ON order_item_transfer_away_domain(order_id);
CREATE INDEX ON order_item_transfer_away_domain(status_id);


CREATE TABLE transfer_away_domain_plan (
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_transfer_away_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER plan_transfer_away_domain_provision_tg
    AFTER UPDATE ON transfer_away_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
    EXECUTE PROCEDURE plan_transfer_away_domain_provision ();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON transfer_away_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
    AFTER UPDATE ON transfer_away_domain_plan
    FOR EACH ROW
    WHEN (
        OLD.status_id <> NEW.status_id
    )
    EXECUTE PROCEDURE order_item_plan_processed ();
