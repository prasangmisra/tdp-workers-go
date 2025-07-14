--
-- table: escrow_data_opensrs
-- description: this table stores the escrow data for OpenSRS tenant.
--
CREATE TABLE  escrow.escrow_data_opensrs (
    domain_name       TEXT NOT NULL,                                       -- Domain Name
    expiry_date       TIMESTAMPTZ,                                         -- Expiration Date
    nameservers       TEXT,                                                -- List of Domain Nameservers
    rt_first_name     TEXT,                                                -- Registrant First Name
    rt_last_name      TEXT,                                                -- Registrant Last Name
    rt_address1       TEXT,                                                -- Registrant Address 1
    rt_address2       TEXT,                                                -- Registrant Address 2
    rt_address3       TEXT,                                                -- Registrant Address 3
    rt_city           TEXT,                                                -- Registrant City
    rt_state          TEXT,                                                -- Registrant State
    rt_postal_code    TEXT,                                                -- Registrant Postal Code
    rt_country_code   TEXT,                                                -- Registrant Country Code
    rt_email_address  TEXT,                                                -- Registrant Email Address
    rt_phone_number   TEXT,                                                -- Registrant Phone Number
    rt_fax_number     TEXT,                                                -- Registrant Fax Number
    ac_first_name     TEXT,                                                -- Admin Contact First Name
    ac_last_name      TEXT,                                                -- Admin Contact Last Name
    ac_address1       TEXT,                                                -- Admin Contact Address 1
    ac_address2       TEXT,                                                -- Admin Contact Address 2
    ac_address3       TEXT,                                                -- Admin Contact Address 3
    ac_city           TEXT,                                                -- Admin Contact City
    ac_state          TEXT,                                                -- Admin Contact State
    ac_postal_code    TEXT,                                                -- Admin Contact Postal Code
    ac_country_code   TEXT,                                                -- Admin Contact Country Code
    ac_email_address  TEXT,                                                -- Admin Contact Email Address
    ac_phone_number   TEXT,                                                -- Admin Contact Phone Number
    ac_fax_number     TEXT,                                                -- Admin Contact Fax Number
    bc_first_name     TEXT,                                                -- Billing Contact First Name
    bc_last_name      TEXT,                                                -- Billing Contact Last Name
    bc_address1       TEXT,                                                -- Billing Contact Address 1
    bc_address2       TEXT,                                                -- Billing Contact Address 2
    bc_address3       TEXT,                                                -- Billing Contact Address 3
    bc_city           TEXT,                                                -- Billing Contact City
    bc_state          TEXT,                                                -- Billing Contact State
    bc_postal_code    TEXT,                                                -- Billing Contact Postal Code
    bc_country_code   TEXT,                                                -- Billing Contact Country Code
    bc_email_address  TEXT,                                                -- Billing Contact Email Address
    bc_phone_number   TEXT,                                                -- Billing Contact Phone Number
    bc_fax_number     TEXT,                                                -- Billing Contact Fax Number
    tc_first_name     TEXT,                                                -- Tech Contact First Name
    tc_last_name      TEXT,                                                -- Tech Contact Last Name
    tc_address1       TEXT,                                                -- Tech Contact Address 1
    tc_address2       TEXT,                                                -- Tech Contact Address 2
    tc_address3       TEXT,                                                -- Tech Contact Address 3
    tc_city           TEXT,                                                -- Tech Contact City
    tc_state          TEXT,                                                -- Tech Contact State
    tc_postal_code    TEXT,                                                -- Tech Contact Postal Code
    tc_country_code   TEXT,                                                -- Tech Contact Country Code
    tc_email_address  TEXT,                                                -- Tech Contact Email Address
    tc_phone_number   TEXT,                                                -- Tech Contact Phone Number
    tc_fax_number     TEXT                                                 -- Tech Contact Fax Number
);
