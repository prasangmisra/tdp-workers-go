-- function: provision_hosting_certificate_create_update_hosting_status
-- description: updates the hosting status to 'Pending Certificate Setup'
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_update_hosting_status() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting
    SET hosting_status_id = tc_id_from_name('hosting_status', 'Pending Certificate Setup')
    WHERE id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
