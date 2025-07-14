-- Update foreign key constraints to delete host references on cascade

-- Update order_item_update_host table
ALTER TABLE order_item_update_host
  DROP CONSTRAINT order_item_update_host_new_host_id_fkey;

-- Update provision_domain_host table
ALTER TABLE provision_domain_host
  DROP CONSTRAINT provision_domain_host_host_id_fkey,
  ADD CONSTRAINT provision_domain_host_host_id_fkey FOREIGN KEY (host_id) REFERENCES host(id) ON DELETE CASCADE;

-- Update provision_host_update table
ALTER TABLE provision_host_update
  DROP CONSTRAINT provision_host_update_host_id_fkey,
  ADD CONSTRAINT provision_host_update_host_id_fkey FOREIGN KEY (host_id) REFERENCES host(id) ON DELETE CASCADE;

-- Update provision_domain_update_add_host table
ALTER TABLE provision_domain_update_add_host
  DROP CONSTRAINT provision_domain_update_add_host_host_id_fkey,
  ADD CONSTRAINT provision_domain_update_add_host_host_id_fkey FOREIGN KEY (host_id) REFERENCES host(id) ON DELETE CASCADE;

-- Update provision_domain_update_rem_host table
ALTER TABLE provision_domain_update_rem_host
  DROP CONSTRAINT provision_domain_update_rem_host_host_id_fkey,
  ADD CONSTRAINT provision_domain_update_rem_host_host_id_fkey FOREIGN KEY (host_id) REFERENCES host(id) ON DELETE CASCADE;
