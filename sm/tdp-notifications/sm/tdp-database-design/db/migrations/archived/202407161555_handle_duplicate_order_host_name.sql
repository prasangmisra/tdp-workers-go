CREATE OR REPLACE FUNCTION order_prevent_if_nameservers_count_is_invalid() RETURNS TRIGGER AS $$
DECLARE
    v_domain        RECORD;
    _min_ns_attr    INT;
    _max_ns_attr    INT;
    _hosts_count    INT;
BEGIN
    SELECT * INTO v_domain
    FROM domain d
             JOIN "order" o ON o.id=NEW.order_id
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id;

    SELECT get_tld_setting(
                   p_key=>'tld.dns.min_nameservers',
                   p_tld_id=>vat.tld_id
           )
    INTO _min_ns_attr
    FROM v_accreditation_tld vat
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    SELECT get_tld_setting(
                   p_key=>'tld.dns.max_nameservers',
                   p_tld_id=>vat.tld_id
           )
    INTO _max_ns_attr
    FROM v_accreditation_tld vat
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    SELECT COUNT(DISTINCT u.host) INTO _hosts_count
    FROM UNNEST(NEW.hosts) AS u(host);

    IF _hosts_count < _min_ns_attr OR _hosts_count > _max_ns_attr THEN
        RAISE EXCEPTION 'Nameserver count must be in this range %-%', _min_ns_attr,_max_ns_attr;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
