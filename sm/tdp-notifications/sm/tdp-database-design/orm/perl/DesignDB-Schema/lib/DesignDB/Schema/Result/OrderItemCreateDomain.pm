use utf8;
package DesignDB::Schema::Result::OrderItemCreateDomain;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderItemCreateDomain

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

=head1 TABLE: C<order_item_create_domain>

=cut 

__PACKAGE__->table("order_item_create_domain");

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

=head2 order_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 status_id

  data_type: 'uuid'
  default_value: tc_id_from_name('order_item_status'::text, 'pending'::text)
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'fqdn'
  is_nullable: 0

=head2 registration_period

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=head2 accreditation_tld_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

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
  "order_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "status_id",
  {
    data_type => "uuid",
    default_value => \"tc_id_from_name('order_item_status'::text, 'pending'::text)",
    is_foreign_key => 1,
    is_nullable => 0,
    size => 16,
  },
  "name",
  { data_type => "fqdn", is_nullable => 0 },
  "registration_period",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
  "accreditation_tld_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

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

=head2 create_domain_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::CreateDomainContact>

=cut 

__PACKAGE__->has_many(
  "create_domain_contacts",
  "DesignDB::Schema::Result::CreateDomainContact",
  { "foreign.create_domain_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 create_domain_nameservers

Type: has_many

Related object: L<DesignDB::Schema::Result::CreateDomainNameserver>

=cut 

__PACKAGE__->has_many(
  "create_domain_nameservers",
  "DesignDB::Schema::Result::CreateDomainNameserver",
  { "foreign.create_domain_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 create_domain_plans

Type: has_many

Related object: L<DesignDB::Schema::Result::CreateDomainPlan>

=cut 

__PACKAGE__->has_many(
  "create_domain_plans",
  "DesignDB::Schema::Result::CreateDomainPlan",
  { "foreign.order_item_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Order>

=cut 

__PACKAGE__->belongs_to(
  "order",
  "DesignDB::Schema::Result::Order",
  { id => "order_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 status

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemStatus>

=cut 

__PACKAGE__->belongs_to(
  "status",
  "DesignDB::Schema::Result::OrderItemStatus",
  { id => "status_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:UFaknmvEasJR8TJTllpm+A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
