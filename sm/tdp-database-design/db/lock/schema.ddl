--
-- table: lock_type
-- description: this table lists all posible lock types which block certain operation
--

CREATE TABLE lock_type (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  UNIQUE (name)
);
