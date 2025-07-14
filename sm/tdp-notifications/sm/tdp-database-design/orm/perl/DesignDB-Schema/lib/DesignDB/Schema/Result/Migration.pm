use utf8;
package DesignDB::Schema::Result::Migration;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Migration - 
Record of schema migrations applied.


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

=head1 TABLE: C<migration>

=cut 

__PACKAGE__->table("migration");

=head1 ACCESSORS

=head2 version

  data_type: 'text'
  is_nullable: 0

Timestamp string of migration file in format YYYYMMDDHHMMSS (must match filename).

=head2 name

  data_type: 'text'
  is_nullable: 0

Name of migration from migration filename.

=head2 applied_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 0
  original: {default_value => \"now()"}

Postgres timestamp when migration was recorded.

=cut 

__PACKAGE__->add_columns(
  "version",
  { data_type => "text", is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "applied_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 0,
    original      => { default_value => \"now()" },
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</version>

=back

=cut 

__PACKAGE__->set_primary_key("version");


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NBOYGPVKyXet61qJ+DGeDQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
