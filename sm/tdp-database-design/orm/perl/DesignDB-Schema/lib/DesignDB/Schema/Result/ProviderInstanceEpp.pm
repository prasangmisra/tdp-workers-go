use utf8;
package DesignDB::Schema::Result::ProviderInstanceEpp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ProviderInstanceEpp

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

=head1 TABLE: C<provider_instance_epp>

=cut 

__PACKAGE__->table("provider_instance_epp");

=head1 ACCESSORS

=head2 host

  data_type: 'text'
  is_nullable: 1

=head2 port

  data_type: 'integer'
  default_value: 700
  is_nullable: 1

=head2 conn_min

  data_type: 'integer'
  default_value: 1
  is_nullable: 1

=head2 conn_max

  data_type: 'integer'
  default_value: 10
  is_nullable: 1

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

=cut 

__PACKAGE__->add_columns(
  "host",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "integer", default_value => 700, is_nullable => 1 },
  "conn_min",
  { data_type => "integer", default_value => 1, is_nullable => 1 },
  "conn_max",
  { data_type => "integer", default_value => 10, is_nullable => 1 },
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "provider_instance_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<provider_instance_epp_provider_instance_id_key>

=over 4

=item * L</provider_instance_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "provider_instance_epp_provider_instance_id_key",
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

=head2 provider_instance_epp_exts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProviderInstanceEppExt>

=cut 

__PACKAGE__->has_many(
  "provider_instance_epp_exts",
  "DesignDB::Schema::Result::ProviderInstanceEppExt",
  { "foreign.provider_instance_epp_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3iAb6nvk87shYENtEFLvHA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
