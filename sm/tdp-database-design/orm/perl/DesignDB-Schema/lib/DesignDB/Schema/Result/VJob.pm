use utf8;
package DesignDB::Schema::Result::VJob;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VJob

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

=head1 TABLE: C<v_job>

=cut 

__PACKAGE__->table("v_job");
__PACKAGE__->result_source_instance->view_definition(" SELECT j.id AS job_id,\n    j.tenant_customer_id,\n    js.name AS job_status_name,\n    jt.name AS job_type_name,\n    j.created_date,\n    j.start_date,\n    j.end_date,\n    j.retry_date,\n    j.retry_count,\n    j.reference_id,\n    jt.reference_table,\n    j.result_msg,\n    j.result_data,\n    j.data,\n    to_jsonb(vtc.*) AS tenant_customer,\n    jt.routing_key,\n    js.is_final AS job_status_is_final,\n    j.event_id\n   FROM (((job j\n     JOIN job_status js ON ((j.status_id = js.id)))\n     JOIN job_type jt ON ((jt.id = j.type_id)))\n     JOIN v_tenant_customer vtc ON ((vtc.id = j.tenant_customer_id)))");

=head1 ACCESSORS

=head2 job_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 job_status_name

  data_type: 'text'
  is_nullable: 1

=head2 job_type_name

  data_type: 'text'
  is_nullable: 1

=head2 created_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 start_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 end_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 retry_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 retry_count

  data_type: 'integer'
  is_nullable: 1

=head2 reference_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 reference_table

  data_type: 'text'
  is_nullable: 1

=head2 result_msg

  data_type: 'text'
  is_nullable: 1

=head2 result_data

  data_type: 'jsonb'
  is_nullable: 1

=head2 data

  data_type: 'jsonb'
  is_nullable: 1

=head2 tenant_customer

  data_type: 'jsonb'
  is_nullable: 1

=head2 routing_key

  data_type: 'text'
  is_nullable: 1

=head2 job_status_is_final

  data_type: 'boolean'
  is_nullable: 1

=head2 event_id

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "job_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "job_status_name",
  { data_type => "text", is_nullable => 1 },
  "job_type_name",
  { data_type => "text", is_nullable => 1 },
  "created_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "start_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "end_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "retry_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "retry_count",
  { data_type => "integer", is_nullable => 1 },
  "reference_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "reference_table",
  { data_type => "text", is_nullable => 1 },
  "result_msg",
  { data_type => "text", is_nullable => 1 },
  "result_data",
  { data_type => "jsonb", is_nullable => 1 },
  "data",
  { data_type => "jsonb", is_nullable => 1 },
  "tenant_customer",
  { data_type => "jsonb", is_nullable => 1 },
  "routing_key",
  { data_type => "text", is_nullable => 1 },
  "job_status_is_final",
  { data_type => "boolean", is_nullable => 1 },
  "event_id",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1xa8/YaI6Q62zR5Y2wjxUw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
