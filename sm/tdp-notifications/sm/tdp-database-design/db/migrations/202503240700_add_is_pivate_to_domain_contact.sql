-- Purpose: Add is_private column to domain_contact table.
--
ALTER TABLE IF EXISTS  public.domain_contact ADD IF NOT EXISTS is_private  bool DEFAULT false NOT NULL;