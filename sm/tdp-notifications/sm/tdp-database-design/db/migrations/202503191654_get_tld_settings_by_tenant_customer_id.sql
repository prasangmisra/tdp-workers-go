-- function: get_tld_setting_by_tenant_customer_id
-- description: Retrieves the value of TLD setting based on provided key and either TLD ID or name, and tenant customer ID.
CREATE OR REPLACE FUNCTION get_tld_setting_by_tenant_customer_id(
    p_key                   TEXT,
    p_tenant_customer_id    UUID,
    p_tld_id                UUID DEFAULT NULL,
    p_tld_name              TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _tenant_id      UUID;
BEGIN
    -- either p_tld_name or p_tld_id must be provided
    IF p_tld_name IS NULL AND p_tld_id IS NULL THEN
        RAISE EXCEPTION 'Either TLD name or TLD ID must be provided';
    END IF;

    -- Get the tenant ID
    SELECT tenant_id INTO _tenant_id
    FROM tenant_customer
    WHERE id = p_tenant_customer_id;

    IF _tenant_id IS NULL THEN
        RAISE NOTICE 'No tenant found for tenant customer ID %', p_tenant_customer_id;
        RETURN NULL;
    END IF;

    -- Retrieve the TLD setting
    RETURN get_tld_setting(
        p_key=>p_key,
        p_tld_id=>p_tld_id,
        p_tld_name=>p_tld_name,
        p_tenant_id=>_tenant_id
    );
END;
$$ LANGUAGE plpgsql;
