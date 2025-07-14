
-- validate escrow_config record
CREATE OR REPLACE TRIGGER trigger_validate_escrow_config
    BEFORE INSERT OR UPDATE ON escrow.escrow_config
    FOR EACH ROW EXECUTE FUNCTION validate_escrow_config();

