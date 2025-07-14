CREATE TABLE no_op_status(
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                    TEXT,
  descr                   TEXT,
  is_final                BOOLEAN,
  is_success              BOOLEAN,
  is_cond                 BOOLEAN
);
CREATE UNIQUE INDEX ON no_op_status(is_final,is_success,is_cond) WHERE is_final;

INSERT INTO no_op_status(name,is_final,is_success,is_cond)
    VALUES
        ('initial',false,false,false),
        ('final',true,true,false),
        ('error',true,false,false);


CREATE TABLE no_op (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name text,
    status_id       UUID NOT NULL REFERENCES no_op_status DEFAULT tc_id_from_name('no_op_status','initial')
);

