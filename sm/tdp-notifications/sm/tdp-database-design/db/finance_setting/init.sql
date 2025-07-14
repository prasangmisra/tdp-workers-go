INSERT INTO finance_setting_type (name, descr)
VALUES
    ('general.margin_cap', 'Cap margin on premium domains at $1,000'),
    ('general.round_up_premium', 'Round to nearest $X increment'),
    ('general.round_up_non_premium', 'Round to nearest $X increment'),
    ('general.currency_fluctuation', 'Alert when currency check brings in a fluctuation of currency relative to the existing current value larger than a certain percent'),
    ('general.icann_fee', 'Cost Component ICANN Fee'),
    ('general.bank_fee', 'Cost Component Bank Fee Percentage'),
    ('general.intercompany_pricing_fee', 'Cost Component Intercompany Pricing Fee Percentage'),
    ('general.icann_fee_currency_type', 'Currency_type for Cost Component ICANN Fee'),

    ('provider_instance_tld.is_linear_registryfee_create', 'Is Linear Registry Fee for order_type Domain Create for TLD'),
    ('provider_instance_tld.is_linear_registryfee_renew', 'Is Linear Registry Fee for order_type Domain Renew for TLD'),
    ('provider_instance_tld.accepts_currency', 'Default Currency for TLD'),
    ('provider_instance_tld.tax_fee', 'Cost Component Tax Fee Percentage Depends on TLD'),

    ('tenant_customer.default_currency', 'Default Currency for Tenant Customer'),
    ('tenant_customer.provider_instance_tld.specific_currency', 'Specific Currency to Bill The Customer for The Specific TLD'), 

    ('tenant.accepts_currencies', 'Currency (Abbreviation) Exempt From Bank Fees'),
    ('tenant.hrs','HRS Tenant Boolean Default FALSE'),
    ('tenant.customer_of','the HRS tenant is a customer of tenant_id');
    
INSERT INTO finance_setting (type_id, value_integer, validity)
VALUES
    (tc_id_from_name('finance_setting_type','general.margin_cap'), 100000, tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type','general.round_up_premium'), 1000,  tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type','general.round_up_non_premium'), 500, tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type','general.currency_fluctuation'), 5, tstzrange('2024-01-01 UTC', 'infinity')),
     -- icann
    (tc_id_from_name('finance_setting_type','general.icann_fee'), 18, tstzrange('2013-01-01 00:00:00 UTC', '2025-07-01 00:00:00 UTC')),
    (tc_id_from_name('finance_setting_type','general.icann_fee'), 20, tstzrange('2025-07-01 00:00:00 UTC', 'infinity')),
    -- bank fee 
    (tc_id_from_name('finance_setting_type','general.bank_fee'), 2, tstzrange('2024-01-01 UTC', 'infinity')),
    -- intercompany fee 
    (tc_id_from_name('finance_setting_type','general.intercompany_pricing_fee'), 5, tstzrange('2024-01-01 UTC', 'infinity'));

INSERT INTO finance_setting (type_id, value_text, validity)
VALUES
    (tc_id_from_name('finance_setting_type','general.icann_fee_currency_type'), 'USD', tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type','provider_instance_tld.accepts_currency'), 'USD', tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type', 'tenant_customer.default_currency'), 'USD', tstzrange('2024-01-01 UTC', 'infinity'));


INSERT INTO finance_setting (type_id, value_text_list, validity)
VALUES
    (tc_id_from_name('finance_setting_type','tenant.accepts_currencies'), ARRAY['USD'], tstzrange('2024-01-01 UTC', 'infinity'));

-- reg_fee_create / reg_fee_renew is_linear
INSERT INTO finance_setting (type_id, value_boolean, validity)
VALUES 
    (tc_id_from_name('finance_setting_type','provider_instance_tld.is_linear_registryfee_create'), 'TRUE', tstzrange('2024-01-01 UTC', 'infinity')),
    (tc_id_from_name('finance_setting_type','provider_instance_tld.is_linear_registryfee_renew'), 'TRUE', tstzrange('2024-01-01 UTC', 'infinity'));

    -- tax fee
INSERT INTO finance_setting (type_id, value_decimal, validity)
VALUES 
    (tc_id_from_name('finance_setting_type','provider_instance_tld.tax_fee'), 0, tstzrange('2024-01-01 UTC', 'infinity'));