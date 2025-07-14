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


