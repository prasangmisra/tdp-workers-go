-- table: provision_hosting_delete
-- description: This table is to provision hosting order with AWS
CREATE TABLE provision_hosting_delete (
  hosting_id              UUID NOT NULL,
  external_order_id       TEXT,
  status                  TEXT REFERENCES hosting_status(name),
  hosting_status_id       UUID REFERENCES hosting_status,
  is_active               BOOLEAN,
  is_deleted              BOOLEAN,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY (id)
) INHERITS (class.audit_trail, class.provision);


-- starts the hosting delete order provision
CREATE TRIGGER provision_hosting_delete_job_tg
  AFTER INSERT ON provision_hosting_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_hosting_delete_job();

-- Trigger when the operation is successful
CREATE TRIGGER provision_hosting_delete_success_tg
  AFTER UPDATE ON provision_hosting_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status', 'completed')
  ) EXECUTE PROCEDURE provision_hosting_delete_success();


---------------- backward compatibility of status and hosting_status_id ----------------

CREATE TRIGGER provision_hosting_delete_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON provision_hosting_delete
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER provision_hosting_delete_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON provision_hosting_delete
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER provision_hosting_delete_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON provision_hosting_delete
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER provision_hosting_delete_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON provision_hosting_delete
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();

--------------------------------- end of backward compatibility ----------------------------
