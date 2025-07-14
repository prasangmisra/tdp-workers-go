-- drop not null contraint from domain table ry columns
ALTER TABLE domain ALTER COLUMN ry_created_date DROP NOT NULL;
ALTER TABLE domain ALTER COLUMN ry_expiry_date DROP NOT NULL;