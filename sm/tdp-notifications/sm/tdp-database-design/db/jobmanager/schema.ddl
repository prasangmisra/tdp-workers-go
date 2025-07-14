--
-- table: job_status
-- description: this table stores various statuses of the jobs
--

CREATE TABLE job_status (
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name          TEXT NOT NULL,
  descr         TEXT NOT NULL,
  is_final      BOOLEAN NOT NULL,
  is_success    BOOLEAN NOT NULL,
  UNIQUE(name)
);

--
-- table: job_type
-- description: this table stores various statuses of the jobs
--

CREATE TABLE job_type (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                    TEXT NOT NULL,
  descr                   TEXT NOT NULL,
  reference_table         TEXT,
  reference_status_table  TEXT,
  reference_status_column TEXT NOT NULL DEFAULT 'status_id',
  routing_key             TEXT,
  is_noop                 BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE(name),
  CHECK( 
    reference_table IS NULL      -- no status update will be done
    OR ( 
      reference_table IS NOT NULL   -- we'll use the reference_status_table to update
      AND reference_status_table IS NOT NULL 
    ) 
  )
);

--
-- table: job
-- description: this table stores jobs that need to be performed
--              on the server in an asynchronous way
--

CREATE TABLE job (
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_customer_id    UUID REFERENCES tenant_customer,
  type_id               UUID NOT NULL REFERENCES job_type,
  status_id             UUID NOT NULL REFERENCES job_status 
                        DEFAULT tc_id_from_name('job_status','created'),
  start_date            TIMESTAMPTZ DEFAULT NOW(),
  end_date              TIMESTAMPTZ,
  retry_count           INT DEFAULT 0,
  retry_interval        INTERVAL,
  max_retries           INT DEFAULT 1,
  reference_id          UUID,
  data                  JSONB,
  result_message        TEXT,
  result_data           JSONB,
  event_id              TEXT,
  parent_id             UUID REFERENCES job(id),
  is_hard_fail          BOOLEAN NOT NULL DEFAULT TRUE,
  created_date          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by            TEXT NOT NULL DEFAULT CURRENT_USER
) INHERITS(class.audit_trail);

-- TODO: partition for performance
-- PARTITION BY RANGE(created_date);

CREATE INDEX ON job(created_date);
CREATE INDEX ON job(event_id);
CREATE INDEX ON job(parent_id);
CREATE INDEX ON job(reference_id);

-- SELECT partition_helper_by_month('job');



--
-- table: job_reference_status_override
-- description: this table contains overrides of job status to reference status
--

CREATE TABLE job_reference_status_override (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  status_id               UUID NOT NULL REFERENCES job_status,
  reference_status_table  TEXT NOT NULL,
  reference_status_id     UUID NOT NULL,
  UNIQUE(status_id, reference_status_table, reference_status_id)
);
