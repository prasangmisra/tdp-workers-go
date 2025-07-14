use utf8;
package DesignDB::Schema::Result::ProviderInstanceHttp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ProviderInstanceHttp

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

=head1 TABLE: C<provider_instance_http>

=cut 

__PACKAGE__->table("provider_instance_http");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 url

  data_type: 'text'
  is_nullable: 1

=head2 api_key

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
  "provider_instance_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "url",
  { data_type => "text", is_nullable => 1 },
  "api_key",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<provider_instance_http_provider_instance_id_key>

=over 4

=item * L</provider_instance_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "provider_instance_http_provider_instance_id_key",
  ["provider_instance_id"],
);

=head1 RELATIONS

=head2 provider_instance

Type: belongs_to

Related object: L<DesignDB::Schema::Result::ProviderInstance>

=cut 

__PACKAGE__->belongs_to(
  "provider_instance",
  "DesignDB::Schema::Result::ProviderInstance",
  { id => "provider_instance_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KPur01odQcG1RCT59VaYww


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
