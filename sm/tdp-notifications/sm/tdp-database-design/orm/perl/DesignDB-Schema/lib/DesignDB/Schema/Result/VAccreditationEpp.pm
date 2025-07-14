use utf8;
package DesignDB::Schema::Result::VAccreditationEpp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VAccreditationEpp

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

=head1 TABLE: C<v_accreditation_epp>

=cut 

__PACKAGE__->table("v_accreditation_epp");
__PACKAGE__->result_source_instance->view_definition(" SELECT t.name AS tenant_name,\n    t.id AS tenant_id,\n    p.id AS provider_id,\n    p.name AS provider_name,\n    a.name AS accreditation_name,\n    a.id AS accreditation_id,\n    ae.id AS accreditation_epp_id,\n    ae.cert_id,\n    ae.clid,\n    ae.pw,\n    COALESCE(ae.host, pie.host) AS host,\n    COALESCE(ae.port, pie.port) AS port,\n    COALESCE(ae.conn_min, pie.conn_min) AS conn_min,\n    COALESCE(ae.conn_max, pie.conn_max) AS conn_max\n   FROM (((((accreditation_epp ae\n     JOIN accreditation a ON ((a.id = ae.accreditation_id)))\n     JOIN tenant t ON ((t.id = a.tenant_id)))\n     JOIN provider_instance pi ON ((pi.id = a.provider_instance_id)))\n     JOIN provider_instance_epp pie ON ((pie.provider_instance_id = a.provider_instance_id)))\n     JOIN provider p ON ((p.id = pi.provider_id)))");

=head1 ACCESSORS

=head2 tenant_name

  data_type: 'text'
  is_nullable: 1

=head2 tenant_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_name

  data_type: 'text'
  is_nullable: 1

=head2 accreditation_name

  data_type: 'text'
  is_nullable: 1

=head2 accreditation_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 accreditation_epp_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 cert_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 clid

  data_type: 'text'
  is_nullable: 1

=head2 pw

  data_type: 'text'
  is_nullable: 1

=head2 host

  data_type: 'text'
  is_nullable: 1

=head2 port

  data_type: 'integer'
  is_nullable: 1

=head2 conn_min

  data_type: 'integer'
  is_nullable: 1

=head2 conn_max

  data_type: 'integer'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "tenant_name",
  { data_type => "text", is_nullable => 1 },
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_name",
  { data_type => "text", is_nullable => 1 },
  "accreditation_name",
  { data_type => "text", is_nullable => 1 },
  "accreditation_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "accreditation_epp_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "cert_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "clid",
  { data_type => "text", is_nullable => 1 },
  "pw",
  { data_type => "text", is_nullable => 1 },
  "host",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "integer", is_nullable => 1 },
  "conn_min",
  { data_type => "integer", is_nullable => 1 },
  "conn_max",
  { data_type => "integer", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:O+dkXF4skr6Nre2w1VU+og


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
