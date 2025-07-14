-- default value ??? 

INSERT INTO promo_type
    ("name", descr)
    VALUES
        ('percent discount', 'A promotion that offers a percentage off the original price.'),
        ('fixed discount', 'A promotion that offers a fixed amount off the original price.'),
        ('fixed price', 'A promotion that offers a product at a fixed promotional price.');


INSERT INTO price_type
        ("name", descr, overrides)
        VALUES
            ('tier', 'The tier price for the named tier. This tier price is attributed to all customer accounts that have been assigned that tier', NULL),
            ('premium', 'The price assigned for a premium domain under the named TLD, calculated as a markup in % on top of the cost indicated in the EPP Fee Check', NULL),
            ('repeating charge', 'A price for a repeating charge, tied to a range of products, that should get billed to a reseller account even where that charge may not be tied to a particular product or cost', NULL);


INSERT INTO price_type
    ("name", descr, overrides)
    VALUES(     
        UNNEST(ARRAY[
            'custom', 
            'custom - cost+'
        ]),
        UNNEST(ARRAY[
            'A custom price, which overrides the assigned tier price for the given product and order type for whichever account(s) it is assigned to. Cannot be combined with Custom - Cost+',
            'A custom price, calculated by the system based on the markup amount indicated - the markup price is automatically added on top of the USD converted cost to determine the price. Cannot be combined with Custom'   
        ]),
        ARRAY[(SELECT id 
        FROM price_type
        WHERE name = 'tier')]
    );

INSERT INTO price_type
    ("name", descr, overrides)
    VALUES
        ('promo - all', 
        'The promotional price assigned to a product and order type for a designated period of time - automatically assigned to all reseller accounts for that brand. Cannot be combined with Promo - Signup',
        ARRAY[(SELECT id 
                FROM price_type
                WHERE name = 'tier'),
            (SELECT id 
                FROM price_type
                WHERE name = 'custom')
        ]), 
        ('promo - signup', 
        'The promotional price assigned to designated reseller accounts (or account groups), for a designated period of time. Resellers have to sign up to receive this pricing. Cannot be combined with Promo - ALL',
        ARRAY[(SELECT id 
                FROM price_type
                WHERE name = 'tier'),
            (SELECT id 
                FROM price_type
                WHERE name = 'custom')
        ]);

INSERT INTO price_type
    ("name", descr, overrides)
    VALUES        
        ( 'promo - custom',
        'The custom promotional price assigned to a designated reseller account (or group), for a designated period of time',
        ARRAY[(SELECT id 
                FROM price_type
                WHERE name = 'promo - all'),
            (SELECT id 
                FROM price_type
                WHERE name = 'promo - signup'),
            (SELECT id 
                FROM price_type
                WHERE name = 'tier'),
            (SELECT id 
                FROM price_type
                WHERE name = 'custom')]);

INSERT INTO price_type
    ("name", descr, overrides)
    VALUES   
        ('custom - premium',
        'The custom price assigned to a reseller account for a premium domain under the named TLD, calculated as a markup in % on top of the cost indicated in the EPP Fee Check',
        ARRAY[(SELECT id 
        FROM price_type
        WHERE name = 'premium')]);

UPDATE price_type
    SET level = CASE 
        WHEN name = 'tier' THEN 1
        WHEN name = 'custom' THEN 2
        WHEN name = 'custom - cost+' THEN 2
        WHEN name = 'promo - all' THEN 3
        WHEN name = 'promo - signup' THEN 3
        WHEN name = 'promo - custom' THEN 4
        WHEN name = 'premium' THEN 10
        WHEN name = 'custom - premium' THEN 11
        WHEN name = 'repeating charge' THEN 100
        ELSE 0  
    END;

INSERT INTO product_cost_range
	(product_id, value)
    VALUES
        (tc_id_from_name('product','domain'), numrange(0, 10000, '[)')), 
        (tc_id_from_name('product','domain'), numrange(10000, 50000, '[)')), 
        (tc_id_from_name('product','domain'), numrange(50000, 150000, '[)')), 
        (tc_id_from_name('product','domain'), numrange(150000, NULL, '[)')); 

INSERT INTO domain_premium_margin 
    (product_cost_range_id, price_type_id, value, start_date)
    VALUES(   
        UNNEST(ARRAY [(SELECT id FROM product_cost_range cr WHERE value @> numrange(1, 10000, '[)')) ,
            (SELECT id FROM product_cost_range cr WHERE value @> numrange(10000, 50000, '[)')),
            (SELECT id FROM product_cost_range cr WHERE value @> numrange(50000, 150000, '[)')), 
            (SELECT id FROM product_cost_range cr WHERE value @> numrange(150000, null, '[)'))]),
        tc_id_from_name('price_type','premium'),
        unnest(array[ 35,30,25,20]), 
        TIMESTAMPTZ '2024-01-01 00:00:00 UTC'); 

INSERT INTO product_tier_type
	(product_id, "name")
SELECT
	tc_id_from_name('product','domain'),
	UNNEST(ARRAY[
        'essential', 
        'advanced',
        'premium',
        'enterprise'
    ]); 

INSERT INTO repeating_charge_type
    (name, descr)
    VALUES 
    ('monthly minimum amount', 'billed monthly minimum amount or transactional amount if it is larger then monthly minimum amount' );

INSERT INTO product_price_strategy
    (product_id, price_type_id, level, iteration_order) --,table_name,  return_parameter_list, function_name)
SELECT
    tc_id_from_name('product','domain'),
    id,
    level, 
    CASE 
        WHEN name = 'tier' THEN 1
        WHEN name = 'custom' OR name = 'custom - cost+' THEN 3
        WHEN name = 'promo - all' THEN 5
        WHEN name = 'promo - signup' OR name = 'promo - custom' THEN 7
        WHEN name = 'premium' OR name = 'custom - premium' THEN 10
        WHEN name = 'repeating charge' THEN 100
        ELSE 0
    END iteration_order
FROM price_type; 

