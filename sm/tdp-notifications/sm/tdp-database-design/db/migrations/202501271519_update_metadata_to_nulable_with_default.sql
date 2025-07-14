ALTER TABLE public.hosting ADD COLUMN metadata_temp jsonb DEFAULT '{}'::jsonb;

UPDATE public.hosting
SET metadata_temp = metadata::jsonb;

ALTER TABLE public.hosting DROP COLUMN metadata;

ALTER TABLE public.hosting RENAME COLUMN metadata_temp TO metadata;

ALTER TABLE hosting ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;


-- Update contact table to make metadata column nullable
ALTER TABLE public.contact ALTER COLUMN metadata DROP NOT NULL;

-- Update domain table to make metadata column nullable
ALTER TABLE public."domain" ALTER COLUMN metadata DROP NOT NULL;

-- Update host table to make metadata column nullable
ALTER TABLE public.host ALTER COLUMN metadata DROP NOT NULL;

-- Update order table to make metadata column nullable
ALTER TABLE public."order" ALTER COLUMN metadata DROP NOT NULL;

-- Update order_contact table to make metadata column nullable
ALTER TABLE public.order_contact ALTER COLUMN metadata DROP NOT NULL;


-- Update order_host table to make metadata column nullable
ALTER TABLE public.order_host ALTER COLUMN metadata DROP NOT NULL;

-- Update order_item_create_domain table to make metadata column nullable
ALTER TABLE public.order_item_create_domain ALTER COLUMN metadata DROP NOT NULL;

-- Update order_item_import_domain table to make metadata column nullable
ALTER TABLE public.order_item_import_domain ALTER COLUMN metadata DROP NOT NULL;

-- Update order_item_transfer_away_domain table to make metadata column nullable
ALTER TABLE public.order_item_transfer_away_domain ALTER COLUMN metadata DROP NOT NULL;

-- Update order_item_transfer_in_domain table to make metadata column nullable
ALTER TABLE public.order_item_transfer_in_domain ALTER COLUMN metadata DROP NOT NULL;

-- Update provision to make metadata column nullable
ALTER TABLE "class".provision ALTER COLUMN order_metadata DROP NOT NULL;

-- Update provision_domain to make metadata column nullable
ALTER TABLE public.provision_domain ALTER COLUMN metadata DROP NOT NULL;

-- Update provision_domain_transfer_in to make metadata column nullable
ALTER TABLE public.provision_domain_transfer_in ALTER COLUMN metadata DROP NOT NULL;

-- Update provision_host to make metadata column nullable
ALTER TABLE public.provision_host ALTER COLUMN metadata DROP NOT NULL;

-- Update validation_rule to make metadata column nullable
ALTER TABLE public.validation_rule ALTER COLUMN metadata DROP NOT NULL;