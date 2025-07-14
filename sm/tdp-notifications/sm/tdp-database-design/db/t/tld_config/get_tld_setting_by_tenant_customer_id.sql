BEGIN;

-- start testing
SELECT * FROM no_plan();

-- Test with valid tenant_customer_id, tld_name and key
SELECT ok(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_name => 'sexy'
            )
    ) IS NOT NULL,
    'should return data for valid key, tenant_customer_id and tld_name'
);

-- Test with valid tenant_customer_id, tld_id and key
SELECT ok(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_id => (SELECT id FROM tld WHERE name = 'sexy')
            )
    ) IS NOT NULL,
    'should return data for valid key, tenant_customer_id and tld_id'
);

-- Test with valid tenant_customer_id, both tld_name and tld_id, and key
SELECT ok(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_id => (SELECT id FROM tld WHERE name = 'sexy'),
                p_tld_name => 'sexy'
            )
    ) IS NOT NULL,
    'should return data for valid key, tenant_customer_id with both tld_name and tld_id'
);

-- Test with non-existent tenant_customer_id
SELECT is(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => '00000000-0000-0000-0000-000000000000',
                p_tld_name => 'sexy'
            )
    ),
    NULL,
    'should return NULL for non-existent tenant_customer_id'
);

-- Test with non-existent tld_name
SELECT is(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_name => 'fake.tld'
            )
    ),
    NULL,
    'should return NULL for non-existent tld_name'
);

-- Test with non-existent tld_id
SELECT is(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'allowed_nameserver_count',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_id => '00000000-0000-0000-0000-000000000000'
            )
    ),
    NULL,
    'should return NULL for non-existent tld_id'
);

-- Test with non-existent key
SELECT is(
    (
        SELECT 
            get_tld_setting_by_tenant_customer_id(
                p_key => 'non_existent_key',
                p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = 'opensrs') LIMIT 1),
                p_tld_name => 'sexy'
            )
    ),
    NULL,
    'should return NULL for non-existent key'
);

-- Test exception when both tld_name and tld_id are NULL
SELECT throws_ok(
    'SELECT get_tld_setting_by_tenant_customer_id(
        p_key => ''allowed_nameserver_count'',
        p_tenant_customer_id => (SELECT id FROM tenant_customer WHERE tenant_id = (SELECT id FROM tenant WHERE name = ''opensrs'') LIMIT 1),
        p_tld_id => NULL,
        p_tld_name => NULL
    )',
    'P0001',
    'Either TLD name or TLD ID must be provided',
    'should throw exception when both tld_name and tld_id are NULL'
);

-- finish testing
SELECT * FROM finish(true);

ROLLBACK;
