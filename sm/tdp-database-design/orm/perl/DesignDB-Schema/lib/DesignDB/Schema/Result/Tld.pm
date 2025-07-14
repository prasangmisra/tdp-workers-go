use utf8;
package DesignDB::Schema::Result::Tld;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Tld

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

=head1 TABLE: C<tld>

=cut 

__PACKAGE__->table("tld");

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

=head2 registry_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 parent_tld_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

If top level domain is for instance co.uk this foreign key refers to uk.

=head2 name

  data_type: 'text'
  is_nullable: 0

The top level domain without a leading dot

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
  "registry_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "parent_tld_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "name",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<tld_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("tld_name_key", ["name"]);

=head1 RELATIONS

=head2 parent_tld

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Tld>

=cut 

__PACKAGE__->belongs_to(
  "parent_tld",
  "DesignDB::Schema::Result::Tld",
  { id => "parent_tld_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 provider_instance_tlds

Type: has_many

Related object: L<DesignDB::Schema::Result::ProviderInstanceTld>

=cut 

__PACKAGE__->has_many(
  "provider_instance_tlds",
  "DesignDB::Schema::Result::ProviderInstanceTld",
  { "foreign.tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 registry

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Registry>

=cut 

__PACKAGE__->belongs_to(
  "registry",
  "DesignDB::Schema::Result::Registry",
  { id => "registry_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 tlds

Type: has_many

Related object: L<DesignDB::Schema::Result::Tld>

=cut 

__PACKAGE__->has_many(
  "tlds",
  "DesignDB::Schema::Result::Tld",
  { "foreign.parent_tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:mu8stJjWy0baAe6HtrZqdw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
