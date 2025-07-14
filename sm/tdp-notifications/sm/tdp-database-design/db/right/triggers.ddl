

CREATE TRIGGER right_enforce_contact_order
BEFORE INSERT OR UPDATE ON "contact_order"
FOR EACH ROW EXECUTE PROCEDURE trg_right_enforce_order();

CREATE TRIGGER right_enforce_domain_order
BEFORE INSERT OR UPDATE ON "domain_order"
FOR EACH ROW EXECUTE PROCEDURE trg_right_enforce_order();

CREATE TRIGGER right_enforce_host_order
BEFORE INSERT OR UPDATE ON "host_order"
FOR EACH ROW EXECUTE PROCEDURE trg_right_enforce_order();
