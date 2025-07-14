use utf8;
package DesignDB::Schema::Result::ProviderProtocol;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ProviderProtocol

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

=head1 TABLE: C<provider_protocol>

=cut 

__PACKAGE__->table("provider_protocol");

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

=head2 supported_protocol_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 is_enabled

  data_type: 'boolean'
  default_value: true
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
  "provider_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "supported_protocol_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "is_enabled",
  { data_type => "boolean", default_value => \"true", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<provider_protocol_provider_id_supported_protocol_id_key>

=over 4

=item * L</provider_id>

=item * L</supported_protocol_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "provider_protocol_provider_id_supported_protocol_id_key",
  ["provider_id", "supported_protocol_id"],
);

=head1 RELATIONS

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

=head2 supported_protocol

Type: belongs_to

Related object: L<DesignDB::Schema::Result::SupportedProtocol>

=cut 

__PACKAGE__->belongs_to(
  "supported_protocol",
  "DesignDB::Schema::Result::SupportedProtocol",
  { id => "supported_protocol_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Gx4WvZ8VvcPWzkNiU0vhxQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
