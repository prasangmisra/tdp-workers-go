--
-- function: order_prevent_if_nameserver_does_not_exist()
-- description: check if nameservers from domain update order data exists
--

CREATE OR REPLACE FUNCTION order_prevent_if_nameserver_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    _hosts_exist  BOOL;
BEGIN

    -- @> operator checks of the first array contains the seconds.
    -- @> can return null if there's no value so we use COALESCE
    SELECT COALESCE(ARRAY_AGG(h.name::FQDN), ARRAY[]::FQDN[]) @> NEW.hosts
    INTO _hosts_exist
    FROM host h
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = NEW.accreditation_tld_id
    JOIN provision_host ph ON
      ph.host_id = h.id
      AND ph.accreditation_id = vat.accreditation_id
    WHERE h.name = ANY(NEW.hosts);

    IF NOT _hosts_exist THEN
        RAISE EXCEPTION 'One or more nameservers do not exist: ''%''', NEW.hosts USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
