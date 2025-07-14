CREATE SCHEMA IF NOT EXISTS class;

CREATE TABLE class.audit (
     created_date          TIMESTAMPTZ DEFAULT NOW(),
     updated_date          TIMESTAMPTZ,
     created_by            TEXT DEFAULT CURRENT_USER,
     updated_by            TEXT
);

CREATE TABLE class.audit_trail (
) INHERITS (class.audit);


CREATE TABLE class.soft_delete (
    deleted_date          TIMESTAMPTZ,
    deleted_by            TEXT
);
