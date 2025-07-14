CREATE TABLE event_type (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    reference_table_name TEXT,
    description TEXT
);

CREATE TABLE  event (
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

CREATE INDEX idx_events_created_at ON event(created_at);
CREATE INDEX idx_events_reference_id ON event(reference_id);

CREATE TABLE event_unprocessed PARTITION OF event
    FOR VALUES IN (FALSE);

CREATE TABLE event_processed PARTITION OF event
    FOR VALUES IN (TRUE);