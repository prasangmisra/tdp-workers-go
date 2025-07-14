use utf8;
package DesignDB::Schema::Result::DomainHost;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::DomainHost

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

=head1 TABLE: C<domain_host>

=cut 

__PACKAGE__->table("domain_host");

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

=head2 domain_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 host_id

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
  "domain_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "host_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<domain_host_domain_id_host_id_key>

=over 4

=item * L</domain_id>

=item * L</host_id>

=back

=cut 

__PACKAGE__->add_unique_constraint("domain_host_domain_id_host_id_key", ["domain_id", "host_id"]);

=head1 RELATIONS

=head2 domain

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Domain>

=cut 

__PACKAGE__->belongs_to(
  "domain",
  "DesignDB::Schema::Result::Domain",
  { id => "domain_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 host

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Host>

=cut 

__PACKAGE__->belongs_to(
  "host",
  "DesignDB::Schema::Result::Host",
  { id => "host_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:nidztYRBuoDYjRGXJwH4RA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
