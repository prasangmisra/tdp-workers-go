CREATE TABLE IF NOT EXISTS event_type (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    reference_table_name TEXT,
    description TEXT
);


CREATE TABLE IF NOT EXISTS event (
     id UUID NOT NULL DEFAULT gen_random_uuid(),
     reference_id UUID,
     tenant_id UUID NOT NULL,
     type_id UUID NOT NULL REFERENCES event_type(id),
     payload JSONB NOT NULL,
     header JSONB,
     is_processed BOOLEAN DEFAULT FALSE,
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
     PRIMARY KEY (id, is_processed)
) PARTITION BY LIST (is_processed);

------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_events_created_at ON event(created_at);
CREATE INDEX IF NOT EXISTS idx_events_reference_id ON event(reference_id);

CREATE TABLE IF NOT EXISTS event_unprocessed PARTITION OF event
    FOR VALUES IN (FALSE);

CREATE TABLE IF NOT EXISTS event_processed PARTITION OF event
    FOR VALUES IN (TRUE);




------------------------------------------------------------
DROP VIEW IF EXISTS v_event CASCADE;

CREATE OR REPLACE VIEW v_event AS
SELECT
    event.*,
    event_type.name AS event_type_name,
    event_type.reference_table_name AS event_type_reference_table_name
FROM event
         JOIN event_type ON event.type_id = event_type.id;

DROP VIEW IF EXISTS v_event_unprocessed CASCADE;
CREATE OR REPLACE VIEW v_event_unprocessed AS
SELECT
    event_unprocessed.*,
    event_type.name AS event_type_name,
    event_type.reference_table_name AS event_type_reference_table_name
FROM event_unprocessed
         JOIN event_type ON event_unprocessed.type_id = event_type.id;



