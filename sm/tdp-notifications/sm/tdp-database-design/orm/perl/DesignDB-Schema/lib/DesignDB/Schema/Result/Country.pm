use utf8;
package DesignDB::Schema::Result::Country;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Country

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

=head1 TABLE: C<country>

=cut 

__PACKAGE__->table("country");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 0

The country's name.

=head2 alpha2

  data_type: 'text'
  is_nullable: 0

The ISO 3166-1 two letter country code, see https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2.

=head2 alpha3

  data_type: 'text'
  is_nullable: 0

=head2 calling_code

  data_type: 'text'
  is_nullable: 1

The country's calling code accord, see https://en.wikipedia.org/wiki/List_of_country_calling_codes.

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
  "alpha2",
  { data_type => "text", is_nullable => 0 },
  "alpha3",
  { data_type => "text", is_nullable => 0 },
  "calling_code",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<country_alpha2_key>

=over 4

=item * L</alpha2>

=back

=cut 

__PACKAGE__->add_unique_constraint("country_alpha2_key", ["alpha2"]);

=head2 C<country_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("country_name_key", ["name"]);

=head1 RELATIONS

=head2 contact_postals

Type: has_many

Related object: L<DesignDB::Schema::Result::ContactPostal>

=cut 

__PACKAGE__->has_many(
  "contact_postals",
  "DesignDB::Schema::Result::ContactPostal",
  { "foreign.cc" => "self.alpha2" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yDH2an7w9OHLab3Ch36GFg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
