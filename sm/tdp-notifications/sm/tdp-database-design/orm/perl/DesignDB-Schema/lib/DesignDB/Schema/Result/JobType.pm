use utf8;
package DesignDB::Schema::Result::JobType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::JobType

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

=head1 TABLE: C<job_type>

=cut 

__PACKAGE__->table("job_type");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 descr

  data_type: 'text'
  is_nullable: 0

=head2 reference_table

  data_type: 'text'
  is_nullable: 1

=head2 reference_status_table

  data_type: 'text'
  is_nullable: 1

=head2 reference_status_column

  data_type: 'text'
  default_value: 'status_id'
  is_nullable: 0

=head2 routing_key

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 0 },
  "reference_table",
  { data_type => "text", is_nullable => 1 },
  "reference_status_table",
  { data_type => "text", is_nullable => 1 },
  "reference_status_column",
  { data_type => "text", default_value => "status_id", is_nullable => 0 },
  "routing_key",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<job_type_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("job_type_name_key", ["name"]);

=head1 RELATIONS

=head2 jobs

Type: has_many

Related object: L<DesignDB::Schema::Result::Job>

=cut 

__PACKAGE__->has_many(
  "jobs",
  "DesignDB::Schema::Result::Job",
  { "foreign.type_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gFroITPvqB5RaZNZsx7v/w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
