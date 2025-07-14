use utf8;
package DesignDB::Schema::Result::AuditTrailLog202301;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::AuditTrailLog202301

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

=head1 TABLE: C<audit_trail_log_202301>

=cut 

__PACKAGE__->table("audit_trail_log_202301");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'audit_trail_log_id_seq'

=head2 table_name

  data_type: 'text'
  is_nullable: 0

=head2 operation

  data_type: 'text'
  is_nullable: 1

=head2 object_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 old_value

  data_type: 'hstore'
  is_nullable: 1

=head2 new_value

  data_type: 'hstore'
  is_nullable: 1

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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:xosIhRkRlplb7iLp2DbJZg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
