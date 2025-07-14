use utf8;
package DesignDB::Schema::Result::AuditTrail;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::AuditTrail

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

=head1 TABLE: C<audit_trail>

=cut 

__PACKAGE__->table("audit_trail");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 relname

  data_type: 'text'
  is_nullable: 0

The relation name of the table that was modified.

=head2 relid

  data_type: 'uuid'
  is_nullable: 0
  size: 16

The id value of relation for the record that was modified.

=head2 values_pre

  data_type: 'jsonb'
  is_nullable: 1

Structure that includes the fields of the relation that were changed, along with their previous values.

=head2 values_post

  data_type: 'jsonb'
  is_nullable: 0

Structure that includes the fields of the relation that were changed, along with their new values.

=head2 change_date

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 1

Timestamp of when the modification occurred.

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "relname",
  { data_type => "text", is_nullable => 0 },
  "relid",
  { data_type => "uuid", is_nullable => 0, size => 16 },
  "values_pre",
  { data_type => "jsonb", is_nullable => 1 },
  "values_post",
  { data_type => "jsonb", is_nullable => 0 },
  "change_date",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:HdDww8cOaTPgZXdlk7wZng


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
