use utf8;
package DesignDB::Schema::Result::ContactPostal;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ContactPostal

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

=head1 TABLE: C<contact_postal>

=cut 

__PACKAGE__->table("contact_postal");

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

=head2 contact_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 is_ascii

  data_type: 'boolean'
  is_nullable: 0

=head2 first_name

  data_type: 'text'
  is_nullable: 1

=head2 last_name

  data_type: 'text'
  is_nullable: 1

=head2 is_org

  data_type: 'boolean'
  is_nullable: 0

=head2 org_name

  data_type: 'text'
  is_nullable: 1

=head2 org_reg

  data_type: 'text'
  is_nullable: 1

=head2 org_vat

  data_type: 'text'
  is_nullable: 1

=head2 org_duns

  data_type: 'text'
  is_nullable: 1

=head2 address1

  data_type: 'text'
  is_nullable: 0

=head2 address2

  data_type: 'text'
  is_nullable: 1

=head2 address3

  data_type: 'text'
  is_nullable: 1

=head2 city

  data_type: 'text'
  is_nullable: 0

=head2 pc

  data_type: 'text'
  is_nullable: 1

=head2 sp

  data_type: 'text'
  is_nullable: 1

=head2 cc

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

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
  "contact_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "is_ascii",
  { data_type => "boolean", is_nullable => 0 },
  "first_name",
  { data_type => "text", is_nullable => 1 },
  "last_name",
  { data_type => "text", is_nullable => 1 },
  "is_org",
  { data_type => "boolean", is_nullable => 0 },
  "org_name",
  { data_type => "text", is_nullable => 1 },
  "org_reg",
  { data_type => "text", is_nullable => 1 },
  "org_vat",
  { data_type => "text", is_nullable => 1 },
  "org_duns",
  { data_type => "text", is_nullable => 1 },
  "address1",
  { data_type => "text", is_nullable => 0 },
  "address2",
  { data_type => "text", is_nullable => 1 },
  "address3",
  { data_type => "text", is_nullable => 1 },
  "city",
  { data_type => "text", is_nullable => 0 },
  "pc",
  { data_type => "text", is_nullable => 1 },
  "sp",
  { data_type => "text", is_nullable => 1 },
  "cc",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<contact_postal_contact_id_is_ascii_key>

=over 4

=item * L</contact_id>

=item * L</is_ascii>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "contact_postal_contact_id_is_ascii_key",
  ["contact_id", "is_ascii"],
);

=head1 RELATIONS

=head2 cc

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Country>

=cut 

__PACKAGE__->belongs_to(
  "cc",
  "DesignDB::Schema::Result::Country",
  { alpha2 => "cc" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 contact

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Contact>

=cut 

__PACKAGE__->belongs_to(
  "contact",
  "DesignDB::Schema::Result::Contact",
  { id => "contact_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:X5N4lNceFbC9c0yJBscX3g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
