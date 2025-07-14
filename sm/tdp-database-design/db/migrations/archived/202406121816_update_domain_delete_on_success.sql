-- add in_redemption_grace_period to provision_domain_delete table
ALTER TABLE provision_domain_delete
ADD COLUMN in_redemption_grace_period BOOLEAN NOT NULL DEFAULT FALSE;

-- function: provision_domain_delete_success
-- description: deletes the domain in the domain table along with contacts and hosts references
CREATE OR REPLACE FUNCTION provision_domain_delete_success() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.in_redemption_grace_period THEN
        INSERT INTO domain_rgp_status(
            domain_id,
            status_id
        ) VALUES (
            NEW.domain_id,
            tc_id_from_name('rgp_status', 'redemption_grace_period')
        );

        UPDATE domain
        SET deleted_date = NOW()
        WHERE id = NEW.domain_id;
    ELSE
        DELETE FROM domain
        WHERE id = NEW.domain_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- alter table domain_host to ON DELETE CASCADE for domain_id
ALTER TABLE domain_host
DROP CONSTRAINT IF EXISTS domain_host_domain_id_fkey;

ALTER TABLE domain_host
ADD CONSTRAINT domain_host_domain_id_fkey
FOREIGN KEY (domain_id) REFERENCES domain(id)
ON DELETE CASCADE;

-- alter table domain_contact to ON DELETE CASCADE for domain_id
ALTER TABLE domain_contact
DROP CONSTRAINT IF EXISTS domain_contact_domain_id_fkey;

ALTER TABLE domain_contact
ADD CONSTRAINT domain_contact_domain_id_fkey
FOREIGN KEY (domain_id) REFERENCES domain(id)
ON DELETE CASCADE;

-- alter table domain_rgp_status to ON DELETE CASCADE for domain_id
ALTER TABLE domain_rgp_status
DROP CONSTRAINT IF EXISTS domain_rgp_status_domain_id_fkey;

ALTER TABLE domain_rgp_status
ADD CONSTRAINT domain_rgp_status_domain_id_fkey
FOREIGN KEY (domain_id) REFERENCES domain(id)
ON DELETE CASCADE;

-- alter table domain_lock to ON DELETE CASCADE for domain_id
ALTER TABLE domain_lock
DROP CONSTRAINT IF EXISTS domain_lock_domain_id_fkey;

ALTER TABLE domain_lock
ADD CONSTRAINT domain_lock_domain_id_fkey
FOREIGN KEY (domain_id) REFERENCES domain(id)
ON DELETE CASCADE;

-- alter table order_item_delete_domain to ON DELETE CASCADE for domain_id
ALTER TABLE order_item_delete_domain
DROP CONSTRAINT IF EXISTS order_item_delete_domain_domain_id_fkey;

-- alter table order_item_update_domain to ON DELETE CASCADE for domain_id
ALTER TABLE order_item_update_domain
DROP CONSTRAINT IF EXISTS order_item_update_domain_domain_id_fkey;

-- alter table order_item_renew_domain to ON DELETE CASCADE for domain_id
ALTER TABLE order_item_renew_domain
DROP CONSTRAINT IF EXISTS order_item_renew_domain_domain_id_fkey;

-- alter table order_item_redeem_domain to ON DELETE CASCADE for domain_id
ALTER TABLE order_item_redeem_domain
DROP CONSTRAINT IF EXISTS order_item_redeem_domain_domain_id_fkey;
