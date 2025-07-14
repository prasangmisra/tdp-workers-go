use utf8;
package DesignDB::Schema::Result::ProviderInstance;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ProviderInstance

=head1 DESCRIPTION

within a backend provider, there can be multiple instances, which could represent
customers or simply buckets where the tlds are placed, each one of these are considered
instances each one with its own credentials, etc.

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

=head1 TABLE: C<provider_instance>

=cut 

__PACKAGE__->table("provider_instance");

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

=head2 provider_id

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

=head2 is_proxy

  data_type: 'boolean'
  is_nullable: 1

whether this provider is forwarding requests to another (hexonet, opensrs, etc.)

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
  "provider_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 1 },
  "is_proxy",
  { data_type => "boolean", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<provider_instance_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("provider_instance_name_key", ["name"]);

=head1 RELATIONS

=head2 accreditations

Type: has_many

Related object: L<DesignDB::Schema::Result::Accreditation>

=cut 

__PACKAGE__->has_many(
  "accreditations",
  "DesignDB::Schema::Result::Accreditation",
  { "foreign.provider_instance_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order_item_strategies

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemStrategy>

=cut 

__PACKAGE__->has_many(
  "order_item_strategies",
  "DesignDB::Schema::Result::OrderItemStrategy",
  { "foreign.provider_instance_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provider

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Provider>

=cut 

__PACKAGE__->belongs_to(
  "provider",
  "DesignDB::Schema::Result::Provider",
  { id => "provider_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 provider_instance_epp

Type: might_have

Related object: L<DesignDB::Schema::Result::ProviderInstanceEpp>

=cut 

__PACKAGE__->might_have(
  "provider_instance_epp",
  "DesignDB::Schema::Result::ProviderInstanceEpp",
  { "foreign.provider_instance_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provider_instance_http

Type: might_have

Related object: L<DesignDB::Schema::Result::ProviderInstanceHttp>

=cut 

__PACKAGE__->might_have(
  "provider_instance_http",
  "DesignDB::Schema::Result::ProviderInstanceHttp",
  { "foreign.provider_instance_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provider_instance_tlds

Type: has_many

Related object: L<DesignDB::Schema::Result::ProviderInstanceTld>

=cut 

__PACKAGE__->has_many(
  "provider_instance_tlds",
  "DesignDB::Schema::Result::ProviderInstanceTld",
  { "foreign.provider_instance_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:q0DRnis58ddrKqMHNHK8vw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
