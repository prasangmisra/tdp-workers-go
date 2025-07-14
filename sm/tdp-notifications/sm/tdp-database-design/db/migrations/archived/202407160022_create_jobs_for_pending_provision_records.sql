-- starts the host create order provision
CREATE OR REPLACE TRIGGER provision_host_job_tg
  AFTER INSERT ON provision_host
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_job();

-- starts the host update order provision
CREATE OR REPLACE TRIGGER provision_host_update_job_tg
  AFTER INSERT ON provision_host_update
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_update_job();

-- starts the contact create order provision
CREATE OR REPLACE TRIGGER provision_contact_job_tg
  AFTER INSERT ON provision_contact
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_contact_job();

-- starts the contact update order provision
CREATE OR REPLACE TRIGGER provision_contact_update_job_tg
  AFTER UPDATE ON provision_contact_update
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_contact_update_job();

-- starts the contact delete order provision
CREATE OR REPLACE TRIGGER provision_contact_delete_job_tg
  AFTER UPDATE ON provision_contact_delete
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_contact_delete_job();

-- starts the domain create order provision
CREATE OR REPLACE TRIGGER provision_domain_job_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_job();

-- starts the domain renew order provision
CREATE OR REPLACE TRIGGER provision_domain_renew_job_tg
  AFTER INSERT ON provision_domain_renew
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_renew_job();

-- starts the domain redeem order provision
CREATE OR REPLACE TRIGGER provision_domain_redeem_job_tg
  AFTER INSERT ON provision_domain_redeem
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_redeem_job();

-- starts the domain delete order provision
CREATE OR REPLACE TRIGGER provision_domain_delete_job_tg
  AFTER INSERT ON provision_domain_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_delete_job();

-- starts the domain update order provision
CREATE OR REPLACE TRIGGER provision_domain_update_job_tg
  AFTER UPDATE ON provision_domain_update
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete 
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_update_job();

-- starts the hosting certificate create order provision
CREATE OR REPLACE TRIGGER provision_hosting_certificate_create_job_tg
  AFTER INSERT ON provision_hosting_certificate_create
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_hosting_certificate_create_job();

-- starts the hosting create order provision
CREATE OR REPLACE TRIGGER provision_hosting_create_job_tg
  AFTER INSERT ON provision_hosting_create
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_hosting_create_job();

-- starts the hosting delete order provision
CREATE OR REPLACE TRIGGER provision_hosting_delete_job_tg
  AFTER INSERT ON provision_hosting_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_hosting_delete_job();

-- starts the hosting update order provision
CREATE OR REPLACE TRIGGER provision_hosting_update_job_tg
  AFTER INSERT ON provision_hosting_update
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_hosting_update_job();
