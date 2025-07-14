-- drop existing constraints
ALTER TABLE secdns_ds_data DROP CONSTRAINT IF EXISTS algorithm_ok;
ALTER TABLE secdns_ds_data DROP CONSTRAINT IF EXISTS digest_type_ok;
ALTER TABLE secdns_key_data DROP CONSTRAINT IF EXISTS algorithm_ok;

-- add new constraints
ALTER TABLE secdns_key_data ADD CONSTRAINT algorithm_ok CHECK (algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254));

ALTER TABLE secdns_ds_data ADD CONSTRAINT algorithm_ok CHECK (algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254));
ALTER TABLE secdns_ds_data ADD CONSTRAINT digest_type_ok CHECK (digest_type IN (1,2,3,4,5,6));
