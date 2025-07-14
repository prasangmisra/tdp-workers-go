use utf8;
package DesignDB::Schema::Result::Registry;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Registry

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

=head1 TABLE: C<registry>

=cut 

__PACKAGE__->table("registry");

=head1 ACCESSORS

=head2 created_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 1
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

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 business_entity_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 descr

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "created_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "created_by",
  { data_type => "text", default_value => \"CURRENT_USER", is_nullable => 1 },
  "updated_by",
  { data_type => "text", is_nullable => 1 },
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "business_entity_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<registry_business_entity_id_key>

=over 4

=item * L</business_entity_id>

=back

=cut 

__PACKAGE__->add_unique_constraint("registry_business_entity_id_key", ["business_entity_id"]);

=head2 C<registry_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("registry_name_key", ["name"]);

=head1 RELATIONS

=head2 business_entity

Type: belongs_to

Related object: L<DesignDB::Schema::Result::BusinessEntity>

=cut 

__PACKAGE__->belongs_to(
  "business_entity",
  "DesignDB::Schema::Result::BusinessEntity",
  { id => "business_entity_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 tlds

Type: has_many

Related object: L<DesignDB::Schema::Result::Tld>

=cut 

__PACKAGE__->has_many(
  "tlds",
  "DesignDB::Schema::Result::Tld",
  { "foreign.registry_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IA9tytSsVBUTyalYBvZi3Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
