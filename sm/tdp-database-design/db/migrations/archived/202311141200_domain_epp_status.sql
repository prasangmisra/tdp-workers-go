CREATE TABLE IF NOT EXISTS epp_status
(
    id    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name  TEXT NOT NULL,
    descr TEXT,
    UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS domain_epp_status
(
    domain_id           UUID NOT NULL REFERENCES domain,
    epp_status_id       UUID NOT NULL REFERENCES epp_status,
    PRIMARY KEY (domain_id, epp_status_id)
);

CREATE OR REPLACE FUNCTION validate_domain_delete_order()
    RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM v_domain_epp_status
        WHERE domain_id = (SELECT id FROM domain WHERE name = NEW.name)
          AND epp_status_name = 'clientDeleteProhibited'
    ) THEN
        RAISE EXCEPTION 'Deleting domains with "clientDeleteProhibited" epp status is not allowed.'
            USING ERRCODE = 'epp_status_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER validate_domain_delete_order_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_delete_order();


CREATE OR REPLACE VIEW v_domain_epp_status AS
SELECT
    d.domain_id,
    d.epp_status_id,
    e.name AS epp_status_name,
    dm.name AS domain_name
FROM
    domain_epp_status d
        INNER JOIN
    epp_status e ON d.epp_status_id = e.id
        INNER JOIN
    domain dm ON d.domain_id = dm.id;




-- Insert EPP status codes into epp_status_codes table
INSERT INTO epp_status (name, descr) VALUES
     ('clientDeleteProhibited', 'This status code tells your domains registry to reject requests to delete the domain.'),
     ('clientHold', 'The domain is on hold at the clients request, meaning it wont be included in the zone file or resolved in DNS.'),
     ('clientRenewProhibited', 'The client is not allowed to request a renewal for the domain.'),
     ('clientTransferProhibited', 'The client is not allowed to request a transfer for the domain.'),
     ('clientUpdateProhibited', 'The client is not allowed to request an update to the domains information.'),
     ('serverDeleteProhibited', 'The server (registry) prohibits the deletion of the domain.'),
     ('serverHold', 'The server has placed the domain on hold, preventing it from being included in the zone file or resolved in DNS.'),
     ('serverRenewProhibited', 'The server prohibits renewal of the domain.'),
     ('serverTransferProhibited', 'The server prohibits domain transfers.'),
     ('serverUpdateProhibited', 'The server prohibits updates to the domain''s information.'),
     ('pendingCreate', 'The domain is in the process of being created and not yet active.'),
     ('pendingDelete', 'The domain is in the process of being deleted.'),
     ('pendingRenew', 'The domain is in the process of being renewed.'),
     ('pendingTransfer', 'The domain is in the process of being transferred.'),
     ('pendingUpdate', 'The domain is in the process of being updated.'),
     ('inactive', 'This status code indicates that delegation information has not been associated with your domain.')
     ON CONFLICT (name) DO NOTHING