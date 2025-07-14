use utf8;
package DesignDB::Schema::Result::AuditTrailLog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::AuditTrailLog

=head1 DESCRIPTION


Record of changes made to tables that inherit from _audit.
Note: Only stored for relations that have an "id" primary index.


=cut 

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut 

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<audit_trail_log>

=cut 

__PACKAGE__->table("audit_trail_log");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'audit_trail_log_id_seq'

=head2 table_name

  data_type: 'text'
  is_nullable: 0


`type` stores the name of the table that was affected by the current
operation.


=head2 operation

  data_type: 'text'
  is_nullable: 1


Stores the type of SQL operation performed and must be one of
`INSERT`, `TRUNCATE`, `UPDATE` or `DELETE`.

Depending on the actual value of this column, `old_value` and
`new_value` might be `NULL` (ie, there's no `new_value` for a
`DELETE` operation).


=head2 object_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 old_value

  data_type: 'hstore'
  is_nullable: 1


Contain data encoded with `hstore`, representing the state of the
affected row before the `operation` was performed. This is stored as
simple text and must be converted back to `hstore` when data is to be
extracted within the database.


=head2 new_value

  data_type: 'hstore'
  is_nullable: 1


Contain data encoded with `hstore`, representing the state of the
affected row after the `operation` was performed. This is stored as
simple text and must be converted back to `hstore` when data is to be
extracted within the database.


=head2 statement_date

  data_type: 'timestamp with time zone'
  default_value: clock_timestamp()
  is_nullable: 1

=head2 created_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 0
  original: {default_value => \"now()"}

=head2 updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 created_by

  data_type: 'text'
  default_value: CURRENT_USER
  is_nullable: 1

=head2 updated_by

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "audit_trail_log_id_seq",
  },
  "table_name",
  { data_type => "text", is_nullable => 0 },
  "operation",
  { data_type => "text", is_nullable => 1 },
  "object_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "old_value",
  { data_type => "hstore", is_nullable => 1 },
  "new_value",
  { data_type => "hstore", is_nullable => 1 },
  "statement_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"clock_timestamp()",
    is_nullable   => 1,
  },
  "created_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 0,
    original      => { default_value => \"now()" },
  },
  "updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "created_by",
  { data_type => "text", default_value => \"CURRENT_USER", is_nullable => 1 },
  "updated_by",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=item * L</created_date>

=back

=cut 

__PACKAGE__->set_primary_key("id", "created_date");


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:2gARLFG67u63yg+UbZMu8A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
