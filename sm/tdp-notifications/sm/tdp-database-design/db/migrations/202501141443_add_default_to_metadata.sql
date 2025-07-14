-- Purpose: Add default value '{}' to metadata column in all tables that have metadata column.

-- Update metadata column in contact table
UPDATE public.contact SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.contact 
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in domain table
UPDATE public.domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.domain 
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in host table
UPDATE public.host SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.host 
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order table
UPDATE public.order SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order 
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order_contact table
UPDATE public.order_contact SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_contact 
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order_host table
UPDATE public.order_host SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_host
ALTER COLUMN metadata SET NOT NULL;


-- Update metadata column in order_item_create_domain table
UPDATE public.order_item_create_domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_item_create_domain 
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order_item_import_domain table
UPDATE public.order_item_import_domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_item_import_domain
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order_item_transfer_away_domain table
UPDATE public.order_item_transfer_away_domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_item_transfer_away_domain
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update metadata column in order_item_transfer_in_domain table
UPDATE public.order_item_transfer_in_domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.order_item_transfer_in_domain
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;

-- Update order_metadata column in provision table
UPDATE class.provision SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE class.provision
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_contact table
UPDATE public.provision_contact SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_contact
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_contact_delete table
UPDATE public.provision_contact_delete SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_contact_delete
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_contact_update table
UPDATE public.provision_contact_update SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_contact_update
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update metadata and order_metadata columns in provision_domain table
UPDATE public.provision_domain SET metadata = '{}'::JSONB WHERE metadata IS NULL;
UPDATE public.provision_domain SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL,
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_delete table
UPDATE public.provision_domain_delete SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_delete
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_delete_host table
UPDATE public.provision_domain_delete_host SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_delete_host
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_redeem table
UPDATE public.provision_domain_redeem SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_redeem
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_renew table
UPDATE public.provision_domain_renew SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_renew
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_transfer_away table
UPDATE public.provision_domain_transfer_away SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_transfer_away
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update metadata, order_metadata column in provision_domain_transfer_in table
UPDATE public.provision_domain_transfer_in SET metadata = '{}'::JSONB WHERE metadata IS NULL;
UPDATE public.provision_domain_transfer_in SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_transfer_in
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_transfer_in_cancel_request table
UPDATE public.provision_domain_transfer_in_cancel_request SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_transfer_in_cancel_request
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_transfer_in_request table
UPDATE public.provision_domain_transfer_in_request SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_transfer_in_request
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_domain_update table
UPDATE public.provision_domain_update SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_domain_update
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;


-- Update metadata column in provision_host table
UPDATE public.provision_host SET metadata = '{}'::JSONB WHERE metadata IS NULL;
UPDATE public.provision_host SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_host
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_host_delete table
UPDATE public.provision_host_delete SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_host_delete
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_host_update table
UPDATE public.provision_host_update SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_host_update
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_hosting_certificate_create table
UPDATE public.provision_hosting_certificate_create SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_hosting_certificate_create
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_hosting_create table
UPDATE public.provision_hosting_create SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_hosting_create
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_hosting_delete table
UPDATE public.provision_hosting_delete SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_hosting_delete
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update order_metadata column in provision_hosting_update table
UPDATE public.provision_hosting_update SET order_metadata = '{}'::JSONB WHERE order_metadata IS NULL;
ALTER TABLE public.provision_hosting_update
ALTER COLUMN order_metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN order_metadata SET NOT NULL;

-- Update metadata column in validation_rule table
UPDATE public.validation_rule SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE public.validation_rule
ALTER COLUMN metadata SET DEFAULT '{}'::JSONB,
ALTER COLUMN metadata SET NOT NULL;