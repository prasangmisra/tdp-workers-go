use utf8;
package DesignDB::Schema::Result::DomainContactType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::DomainContactType

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

=head1 TABLE: C<domain_contact_type>

=cut 

__PACKAGE__->table("domain_contact_type");

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
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<domain_contact_type_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("domain_contact_type_name_key", ["name"]);

=head1 RELATIONS

=head2 create_domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::CreateDomainContact>

=cut 

__PACKAGE__->has_many(
  "create_domain_contacts",
  "DesignDB::Schema::Result::CreateDomainContact",
  { "foreign.domain_contact_type_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::DomainContact>

=cut 

__PACKAGE__->has_many(
  "domain_contacts",
  "DesignDB::Schema::Result::DomainContact",
  { "foreign.domain_contact_type_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomainContact>

=cut 

__PACKAGE__->has_many(
  "provision_domain_contacts",
  "DesignDB::Schema::Result::ProvisionDomainContact",
  { "foreign.contact_type_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:P8vCqJ+52fcSeoCJy4YotQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
