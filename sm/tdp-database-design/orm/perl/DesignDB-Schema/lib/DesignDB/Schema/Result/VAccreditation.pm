use utf8;
package DesignDB::Schema::Result::VAccreditation;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VAccreditation

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
__PACKAGE__->table_class("DBIx::Class::ResultSource::View");

=head1 TABLE: C<v_accreditation>

=cut 

__PACKAGE__->table("v_accreditation");
__PACKAGE__->result_source_instance->view_definition(" SELECT a.tenant_id,\n    a.id AS accreditation_id,\n    pi.id AS provider_instance_id,\n    p.id AS provider_id,\n    tn.name AS tenant_name,\n    a.name AS accreditation_name,\n    p.name AS provider_name,\n    pi.name AS provider_instance_name,\n    pi.is_proxy\n   FROM (((accreditation a\n     JOIN tenant tn ON ((tn.id = a.tenant_id)))\n     JOIN provider_instance pi ON ((pi.id = a.provider_instance_id)))\n     JOIN provider p ON ((p.id = pi.provider_id)))");

=head1 ACCESSORS

=head2 tenant_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 accreditation_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_name

  data_type: 'text'
  is_nullable: 1

=head2 accreditation_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_instance_name

  data_type: 'text'
  is_nullable: 1

=head2 is_proxy

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "accreditation_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_name",
  { data_type => "text", is_nullable => 1 },
  "accreditation_name",
  { data_type => "text", is_nullable => 1 },
  "provider_name",
  { data_type => "text", is_nullable => 1 },
  "provider_instance_name",
  { data_type => "text", is_nullable => 1 },
  "is_proxy",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1fCnuB63pflHKSeLe5swGQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
