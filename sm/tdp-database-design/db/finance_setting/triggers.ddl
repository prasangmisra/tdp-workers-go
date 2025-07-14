-- 1. Execute check_finance_setting_constraints_tg first 
CREATE TRIGGER a_check_finance_setting_constraints_tg
	BEFORE INSERT OR UPDATE ON finance_setting
	FOR EACH ROW 
	EXECUTE FUNCTION check_finance_setting_constraints();

-- 2. Execute finance_setting_insert_tg second
CREATE TRIGGER b_finance_setting_insert_tg
	BEFORE INSERT ON finance_setting
	FOR EACH ROW
	EXECUTE FUNCTION finance_setting_insert();	