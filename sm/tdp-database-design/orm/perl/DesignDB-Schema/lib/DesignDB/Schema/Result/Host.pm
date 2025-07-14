use utf8;
package DesignDB::Schema::Result::Host;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Host - host objects

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

=head1 TABLE: C<host>

=cut 

__PACKAGE__->table("host");

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

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 domain_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

if the host is a sub domain of a registered name, we will add the reference here.

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
  "name",
  { data_type => "text", is_nullable => 0 },
  "domain_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<host_tenant_customer_id_name_key>

=over 4

=item * L</tenant_customer_id>

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "host_tenant_customer_id_name_key",
  ["tenant_customer_id", "name"],
);

=head1 RELATIONS

=head2 domain

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Domain>

=cut 

__PACKAGE__->belongs_to(
  "domain",
  "DesignDB::Schema::Result::Domain",
  { id => "domain_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 domain_hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::DomainHost>

=cut 

__PACKAGE__->has_many(
  "domain_hosts",
  "DesignDB::Schema::Result::DomainHost",
  { "foreign.host_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 host_addrs

Type: has_many

Related object: L<DesignDB::Schema::Result::HostAddr>

=cut 

__PACKAGE__->has_many(
  "host_addrs",
  "DesignDB::Schema::Result::HostAddr",
  { "foreign.host_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domain_hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomainHost>

=cut 

__PACKAGE__->has_many(
  "provision_domain_hosts",
  "DesignDB::Schema::Result::ProvisionDomainHost",
  { "foreign.host_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionHost>

=cut 

__PACKAGE__->has_many(
  "provision_hosts",
  "DesignDB::Schema::Result::ProvisionHost",
  { "foreign.host_id" => "self.id" },
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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:lReTA8XBJGB21a8gtAjJLw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
