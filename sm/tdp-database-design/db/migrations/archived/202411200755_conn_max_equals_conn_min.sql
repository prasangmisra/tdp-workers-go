-- alter table domain_host to ON DELETE CASCADE for domain_id
ALTER TABLE class.epp_setting
DROP CONSTRAINT IF EXISTS epp_setting_check;

ALTER TABLE class.epp_setting
ADD CONSTRAINT epp_setting_check
CHECK (
    conn_min > 0 AND conn_max > 0
    AND conn_max >= conn_min
);
