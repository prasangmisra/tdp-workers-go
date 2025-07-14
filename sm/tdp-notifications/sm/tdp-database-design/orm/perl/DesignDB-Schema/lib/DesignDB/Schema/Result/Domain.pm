use utf8;
package DesignDB::Schema::Result::Domain;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Domain

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

=head1 TABLE: C<domain>

=cut 

__PACKAGE__->table("domain");

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

=head2 tenant_customer_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 accreditation_tld_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 auth_info

  data_type: 'text'
  is_nullable: 1

=head2 roid

  data_type: 'text'
  is_nullable: 1

=head2 ry_created_date

  data_type: 'timestamp with time zone'
  is_nullable: 0

=head2 ry_expiry_date

  data_type: 'timestamp with time zone'
  is_nullable: 0

=head2 ry_updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 ry_transfered_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 expiry_date

  data_type: 'timestamp with time zone'
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
  "tenant_customer_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "accreditation_tld_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "auth_info",
  { data_type => "text", is_nullable => 1 },
  "roid",
  { data_type => "text", is_nullable => 1 },
  "ry_created_date",
  { data_type => "timestamp with time zone", is_nullable => 0 },
  "ry_expiry_date",
  { data_type => "timestamp with time zone", is_nullable => 0 },
  "ry_updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "ry_transfered_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "expiry_date",
  { data_type => "timestamp with time zone", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<domain_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("domain_name_key", ["name"]);

=head1 RELATIONS

=head2 accreditation_tld

Type: belongs_to

Related object: L<DesignDB::Schema::Result::AccreditationTld>

=cut 

__PACKAGE__->belongs_to(
  "accreditation_tld",
  "DesignDB::Schema::Result::AccreditationTld",
  { id => "accreditation_tld_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::DomainContact>

=cut 

__PACKAGE__->has_many(
  "domain_contacts",
  "DesignDB::Schema::Result::DomainContact",
  { "foreign.domain_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 domain_hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::DomainHost>

=cut 

__PACKAGE__->has_many(
  "domain_hosts",
  "DesignDB::Schema::Result::DomainHost",
  { "foreign.domain_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::Host>

=cut 

__PACKAGE__->has_many(
  "hosts",
  "DesignDB::Schema::Result::Host",
  { "foreign.domain_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domains_renew

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomainRenew>

=cut 

__PACKAGE__->has_many(
  "provision_domains_renew",
  "DesignDB::Schema::Result::ProvisionDomainRenew",
  { "foreign.domain_id" => "self.id" },
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
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:E4F0xDD2q2++YqDkzA1QrQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
