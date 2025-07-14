use utf8;
package DesignDB::Schema::Result::AccreditationEpp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::AccreditationEpp

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

=head1 TABLE: C<accreditation_epp>

=cut 

__PACKAGE__->table("accreditation_epp");

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

=head2 accreditation_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 cert_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 clid

  data_type: 'text'
  is_nullable: 0

=head2 pw

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
  "accreditation_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "cert_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "clid",
  { data_type => "text", is_nullable => 0 },
  "pw",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 accreditation

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Accreditation>

=cut 

__PACKAGE__->belongs_to(
  "accreditation",
  "DesignDB::Schema::Result::Accreditation",
  { id => "accreditation_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 cert

Type: belongs_to

Related object: L<DesignDB::Schema::Result::TenantCert>

=cut 

__PACKAGE__->belongs_to(
  "cert",
  "DesignDB::Schema::Result::TenantCert",
  { id => "cert_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0bLMalRu7JgdCSq8WtqWfQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
