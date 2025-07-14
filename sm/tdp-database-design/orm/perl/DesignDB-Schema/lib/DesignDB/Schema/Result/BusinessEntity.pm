use utf8;
package DesignDB::Schema::Result::BusinessEntity;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::BusinessEntity

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

=head1 TABLE: C<business_entity>

=cut 

__PACKAGE__->table("business_entity");

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

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 descr

  data_type: 'text'
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
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<business_entity_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("business_entity_name_key", ["name"]);

=head1 RELATIONS

=head2 customer

Type: might_have

Related object: L<DesignDB::Schema::Result::Customer>

=cut 

__PACKAGE__->might_have(
  "customer",
  "DesignDB::Schema::Result::Customer",
  { "foreign.business_entity_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provider

Type: might_have

Related object: L<DesignDB::Schema::Result::Provider>

=cut 

__PACKAGE__->might_have(
  "provider",
  "DesignDB::Schema::Result::Provider",
  { "foreign.business_entity_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 registry

Type: might_have

Related object: L<DesignDB::Schema::Result::Registry>

=cut 

__PACKAGE__->might_have(
  "registry",
  "DesignDB::Schema::Result::Registry",
  { "foreign.business_entity_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tenants

Type: has_many

Related object: L<DesignDB::Schema::Result::Tenant>

=cut 

__PACKAGE__->has_many(
  "tenants",
  "DesignDB::Schema::Result::Tenant",
  { "foreign.business_entity_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GJ7p+G1Na95JFUJCnvKM+A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
