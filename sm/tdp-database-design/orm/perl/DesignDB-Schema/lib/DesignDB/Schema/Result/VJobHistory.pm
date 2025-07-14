use utf8;
package DesignDB::Schema::Result::VJobHistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VJobHistory

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

=head1 TABLE: C<v_job_history>

=cut 

__PACKAGE__->table("v_job_history");
__PACKAGE__->result_source_instance->view_definition(" SELECT at.created_date,\n    at.statement_date,\n    at.operation,\n    jt.name AS job_type_name,\n    at.object_id AS job_id,\n    js.name AS status_name,\n    (at.new_value -> 'event_id'::text) AS event_id\n   FROM ((audit_trail_log at\n     JOIN job_status js ON ((js.id = (COALESCE((at.new_value -> 'status_id'::text), (at.old_value -> 'status_id'::text)))::uuid)))\n     JOIN job_type jt ON ((jt.id = (COALESCE((at.new_value -> 'type_id'::text), (at.old_value -> 'type_id'::text)))::uuid)))\n  WHERE (at.table_name = 'job'::text)\n  ORDER BY at.created_date");

=head1 ACCESSORS

=head2 created_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 statement_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 operation

  data_type: 'text'
  is_nullable: 1

=head2 job_type_name

  data_type: 'text'
  is_nullable: 1

=head2 job_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 status_name

  data_type: 'text'
  is_nullable: 1

=head2 event_id

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "created_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "statement_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "operation",
  { data_type => "text", is_nullable => 1 },
  "job_type_name",
  { data_type => "text", is_nullable => 1 },
  "job_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "status_name",
  { data_type => "text", is_nullable => 1 },
  "event_id",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Giswvq63zOmN3vzGI6/2Pw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
