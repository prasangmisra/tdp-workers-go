CREATE OR REPLACE FUNCTION attribute_update() RETURNS TRIGGER AS $$
DECLARE
payload JSONB;
BEGIN

    IF NEW.is_default THEN
        EXECUTE
            FORMAT('INSERT INTO attr_value(key_id,value_%s,tld_id,tenant_id) VALUES($1,$2::%s,$3,$4)',NEW.data_type_name,NEW.data_type)
            USING NEW.key_id,NEW.value,NEW.tld_id,NEW.tenant_id;
    ELSE
        EXECUTE
            FORMAT(
                'UPDATE attr_value SET value_%s=$1::%s WHERE key_id=$2 AND tenant_id=$3 AND tld_id=$4',
                NEW.data_type_name,
                NEW.data_type
            )
            USING NEW.value,NEW.key_id, NEW.tenant_id, NEW.tld_id;
    END IF;

    payload := JSONB_BUILD_OBJECT(
        'tld_name', NEW.tld_name,
        'tenant_name',NEW.tenant_name,
        'key',NEW.key,
        'value', NEW.value,
        'data_type', NEW.data_type
    );

    PERFORM notify_event('cache_update', 'attribute_update_notify', payload::TEXT);

    RETURN NEW;
END
$$ LANGUAGE PLPGSQL;
