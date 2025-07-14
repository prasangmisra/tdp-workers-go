use utf8;
package DesignDB::Schema::Result::Contact;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Contact - Provides the basis for extensible contacts.

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

=head1 TABLE: C<contact>

=cut 

__PACKAGE__->table("contact");

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

=head2 deleted_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 deleted_by

  data_type: 'text'
  is_nullable: 1

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 email

  data_type: 'text'
  is_nullable: 1

=head2 voice

  data_type: 'text'
  is_nullable: 1

=head2 fax

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
  "deleted_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "deleted_by",
  { data_type => "text", is_nullable => 1 },
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "tenant_customer_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "email",
  { data_type => "text", is_nullable => 1 },
  "voice",
  { data_type => "text", is_nullable => 1 },
  "fax",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 contact_postals

Type: has_many

Related object: L<DesignDB::Schema::Result::ContactPostal>

=cut 

__PACKAGE__->has_many(
  "contact_postals",
  "DesignDB::Schema::Result::ContactPostal",
  { "foreign.contact_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::DomainContact>

=cut 

__PACKAGE__->has_many(
  "domain_contacts",
  "DesignDB::Schema::Result::DomainContact",
  { "foreign.contact_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionContact>

=cut 

__PACKAGE__->has_many(
  "provision_contacts",
  "DesignDB::Schema::Result::ProvisionContact",
  { "foreign.contact_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomainContact>

=cut 

__PACKAGE__->has_many(
  "provision_domain_contacts",
  "DesignDB::Schema::Result::ProvisionDomainContact",
  { "foreign.contact_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tenant_customer

Type: belongs_to

Related object: L<DesignDB::Schema::Result::TenantCustomer>

=cut 

__PACKAGE__->belongs_to(
  "tenant_customer",
  "DesignDB::Schema::Result::TenantCustomer",
  { id => "tenant_customer_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BRlpsyQzBzshfB4KwBi39Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
