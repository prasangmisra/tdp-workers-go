use utf8;
package DesignDB::Schema::Result::Accreditation;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Accreditation

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

=head1 TABLE: C<accreditation>

=cut 

__PACKAGE__->table("accreditation");

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

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 tenant_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 service_range

  data_type: 'tstzrange'
  default_value: '(-infinity,infinity)'
  is_nullable: 0

This attribute serves to limit the applicability of a relation over time.

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
  "name",
  { data_type => "text", is_nullable => 0 },
  "tenant_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "provider_instance_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "service_range",
  {
    data_type     => "tstzrange",
    default_value => "(-infinity,infinity)",
    is_nullable   => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<accreditation_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("accreditation_name_key", ["name"]);

=head1 RELATIONS

=head2 accreditation_epps

Type: has_many

Related object: L<DesignDB::Schema::Result::AccreditationEpp>

=cut 

__PACKAGE__->has_many(
  "accreditation_epps",
  "DesignDB::Schema::Result::AccreditationEpp",
  { "foreign.accreditation_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 accreditation_tlds

Type: has_many

Related object: L<DesignDB::Schema::Result::AccreditationTld>

=cut 

__PACKAGE__->has_many(
  "accreditation_tlds",
  "DesignDB::Schema::Result::AccreditationTld",
  { "foreign.accreditation_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

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

=head2 tenant

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Tenant>

=cut 

__PACKAGE__->belongs_to(
  "tenant",
  "DesignDB::Schema::Result::Tenant",
  { id => "tenant_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5tm9IRRrd648Ny76az08+A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
