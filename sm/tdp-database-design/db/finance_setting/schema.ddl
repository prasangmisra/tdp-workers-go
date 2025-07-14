--
-- table: finance_setting_type
-- description: table stores the list of finance_setting names 
-- name MUST have the parameter.name f.e. 'provider_instance_tld.accepted_currency' 

CREATE TABLE finance_setting_type (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT NOT NULL, 
    descr                   TEXT NOT NULL,
    UNIQUE ("name")
);

CREATE INDEX idx_finance_setting_type_name ON finance_setting_type (name);

--
-- table: finance_setting
-- description:  table to store default/overriten values either per tld, or per registry, or per tenant or per tenant_customer

CREATE TABLE finance_setting (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   UUID REFERENCES tenant,
    tenant_customer_id          UUID REFERENCES tenant_customer,
    provider_instance_tld_id    UUID REFERENCES provider_instance_tld,
    type_id     UUID NOT NULL REFERENCES finance_setting_type, 
    value_integer               INTEGER, 
    value_decimal               DECIMAL(19, 4), 
    value_text                  TEXT, 
    value_uuid                  UUID,  
    value_boolean               BOOLEAN, 
    value_text_list             TEXT[], 
    validity 				    TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (type_id WITH=, 
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
        COALESCE(tenant_customer_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
        COALESCE(provider_instance_tld_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
        validity WITH &&) 
) INHERITS (class.audit, class.soft_delete);

CREATE INDEX idx_finance_setting_tenant_id ON finance_setting (tenant_id);
CREATE INDEX idx_finance_setting_tenant_customer_id ON finance_setting (tenant_customer_id);
CREATE INDEX idx_finance_setting_provider_instance_tld_id ON finance_setting (provider_instance_tld_id);
CREATE INDEX idx_type_id ON finance_setting (type_id);

