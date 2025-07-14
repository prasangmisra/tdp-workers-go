INSERT INTO period_type("name")
    VALUES 
    ('month'),
    ('quarter'),
    ('year'),
    ('transaction'); 

INSERT INTO order_type_period_type
    (order_type_id, period_type_id)
    SELECT  
        ot.id, 
        CASE WHEN ot.name IN ('create','renew') THEN tc_id_from_name('period_type', 'year')
        ELSE tc_id_from_name('period_type', 'transaction')
        END
    FROM order_type ot
    JOIN product p ON ot.product_id = p.id
    WHERE p.name = 'domain';

-- Currency with conversion coefficients:  1 CAD = value $USD !!! 
INSERT INTO currency_type (name, descr, fraction)
    VALUES 
        ('AUD','Australia Dollar', 100), 
        ('CAD','Canada Dollar', 100), 
        ('CHF','Swiss Franc', 100),
        ('CNY','China Yuan', 100),
        ('EUR','Euro', 100), 
        ('GBP','Great Britain Pound', 100),
        ('INR','Indian Rupee', 100), 
        ('JPY','Japanese Yen', 100),
        ('NZD','New Zealand Dollar', 100),
        ('PEN','Peru Sol', 100),
        ('SEK','Sweden Krona', 100); 
        ---
        --('SGD','Singapore Dollar', 100), 
        --('DKK','Denmark Krone', 100), 
        --('ZAR','South African Rand', 100), 
        --('LKR','Sri Lanka Rupee', 100);

INSERT INTO currency_exchange_rate (currency_type_id, value, validity) 
    VALUES 
        (tc_id_from_name('currency_type', 'AUD'), 0.65885, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'CAD'), 0.75885, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'CHF'), 1.27641, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'CNY'), 0.14637, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'EUR'), 1.0924, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'GBP'), 1.27641, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'INR'), 0.01191, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'JPY'), 0.00679, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'NZD'), 0.6315, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'PEN'), 0.2925, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'SEK'), 0.1065, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        (tc_id_from_name('currency_type', 'USD'), 1.0000, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, 'infinity', '[]'));         
        --(tc_id_from_name('currency_type', 'SGD'), 5, 0.75498, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        --(tc_id_from_name('currency_type', 'DKK'), 5, 0.14637, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        --(tc_id_from_name('currency_type', 'ZAR'), 5, 0.05475, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
        --(tc_id_from_name('currency_type', 'LKR'), 5, 0.00332, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone));

-- Cost Type
INSERT INTO cost_type
    ("name", descr)
    VALUES( 
        UNNEST(ARRAY[
            'fee'
            ,'repeating fee'
        ]),
        UNNEST(ARRAY[
            'The total cost for a product and order type for a given brand, vendor, product, order type, period, and validity.'
	        ,'A repeating cost that needs to be tracked for a vendor or product but is not tied to any specific order or price, e.g., a yearly accreditation fee.'
        ])
    ); 

-- Cost Component Type
INSERT INTO cost_component_type 
    ("name", cost_type_id, is_periodic, is_percent)
    VALUES 
    ('icann fee', tc_id_from_name('cost_type', 'fee'), TRUE, FALSE), 
    ('bank fee', tc_id_from_name('cost_type', 'fee'), TRUE, TRUE), 
    ('sales tax fee', tc_id_from_name('cost_type', 'fee'), TRUE,  TRUE), 
    ('intercompany pricing fee', tc_id_from_name('cost_type', 'fee'), TRUE,  TRUE), 
    ('registry fee', tc_id_from_name('cost_type', 'fee'), TRUE,  FALSE), 
    ('manual processing fee', tc_id_from_name('cost_type', 'fee'), FALSE, FALSE);

-- Product Cost Calculation
INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id,
        tc_id_from_name('cost_component_type', 'icann fee'), 
        1, 
        TRUE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in');

INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id, 
        tc_id_from_name('cost_component_type', 'bank fee'), 
        10, 
        TRUE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in', 'redeem');

INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id, 
        tc_id_from_name('cost_component_type', 'sales tax fee'), 
        11,  
        TRUE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in', 'redeem');

INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id, 
        tc_id_from_name('cost_component_type', 'intercompany pricing fee'), 
        12,  
        FALSE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in', 'redeem');
    
INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id, 
        tc_id_from_name('cost_component_type', 'registry fee'), 
        30, 
        TRUE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in', 'redeem');

INSERT INTO cost_product_strategy
    (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
    SELECT 
        ot.id, 
        tc_id_from_name('cost_component_type', 'manual processing fee'), 
        20, 
        TRUE
    FROM order_type ot
    WHERE ot.product_id = tc_id_from_name('product','domain') 
    AND ot.name IN ('create','renew', 'transfer_in', 'redeem');

