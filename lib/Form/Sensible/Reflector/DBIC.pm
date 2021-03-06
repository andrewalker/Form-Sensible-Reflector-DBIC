package Form::Sensible::Reflector::DBIC;
use Moose;
use namespace::autoclean;
extends 'Form::Sensible::Reflector';

with 'Form::Sensible::Reflector::DBIC::Role::FieldClassOptions',
  'Form::Sensible::Reflector::DBIC::Role::FieldTypeMap';

our $VERSION = "0.349";
$VERSION = eval $VERSION;

# ABSTRACT: A Form::Sensible::Reflector subclass to reflect off of DBIC schema classes

=head1 NAME

Form::Sensible::Reflector::DBIC - A reflector class based on Form::Sensible and Form::Sensible::Reflector

=cut

=head1 SYNOPSIS

	my $schema = TestSchema->connect('dbi:SQLite::memory:');
	$schema->deploy;
	use Form::Sensible;
	use Form::Sensible::Reflector::DBIC;
	## name must reflect the table which we are reflecting

	my $dt = DateTime->now;

	my $reflector = Form::Sensible::Reflector::DBIC->new();
	my $form      = $reflector->reflect_from(
	    $schema->resultset("Test"),
	    {
	        form   => { name => 'test' },
	         with_trigger => 1
	    }
	);
	my $renderer = Form::Sensible->get_renderer('HTML');

	$form->set_values( { date => $dt } );
	my $output = $renderer->render($form)->complete;

=head1 DESCRIPTION

Form::Sensible::DBIC::Reflector allows you to create Form::Sensible forms from
DBIx::Class objects.

=head1 METHODS

=head2 reflect_from

    my $generated_form = $reflector->reflect_from($data_source, $options);

The $data_source parameter can be a DBIx::Class resultsource such as
$schema->resultset('Table'), or a DBIx::Class::Row object such as
$schema->resultset('Table')->find( 1 );

Since the reflect_from method is actually provided by Form::Sensible itself,
please see the Form::Sensible::Reflector documentation for more information
on the reflect_from method.

=head1 CONFIGURATION OF FIELDS

Form::Sensible::Reflector::DBIC was designed with the intention that as much
configuration as possible can be done in the definition of the
DBIx::Class::ResultSource objects. While the ResultSource definition is used
to programatically generate as much of the Form::Sensible::Field definitions
as possible, it is possible to add to the Field generated. This is done with
several items that can be added to the columinfo hash in the call to add_columns():

=over 4

=item validation

The validation hashref is used just as the validation hashref atribute in L<Form::Sensible::Field>.
It is typically used by L<Form::Sensible::Validator> in order
to create validation rules for form input values. As specified by
Form::Sensible::Validator, it can contain keys C<required>, C<code>, and C<regex>.

=item render_hints

The render_hints hashref also gets passed to L<Form::Sensible::Field> as the
render_hints attribute to the C<create_from_flattened> constructor.

=item fs_definition

The C<fs_definition> hashref can be used to completely override the intelligence
ordinarily used to generate the Form::Sensible::Field definition. If this hashref
is present, each key in it is used to completely overwrite the key in the
Form::Sensible::Field definition. Any of the attributes accepted by
Form::Sensible::Field are acceptable here. Note that one could alternatively
specify C<validation> and C<render_hints> options here.

=item fs_ignore

If this key is present with a true value, this column will not be included in the
Form::Sensible form at all. This may be handy for skipping over timestamps automatically
populated by the database, for instance.

=back

For example:

    __PACKAGE__->add_columns(
        'id',
        {
            data_type         => 'integer',
            is_auto_increment => 1,
            is_nullable       => 0
        },
        'phone_number',
        {
            data_type  => 'varchar',
            validation => { regex => qr/[-\d]+/ }, # passed to Form::Sensible::Field
        }
    );
    __PACKAGE__->set_primary_key('id');  # Defaults to hidden in the form

=head1 WAYS TO REFLECT

=over 4

=item From a ResultSet:

    my $reflector = Form::Sensible::Reflector::DBIC->new();
    my $form      = $reflector->reflect_from( $schema->resultset("Test"),
      { 
        form => 
        { 
          name => 'test' 
        }, 
        with_trigger => 1 
      } 
    );

=item From a Row object:
  
  my $reflector     = Form::Sensible::Reflector::DBIC->new();
  my $row           = $schema->resultset('Herp')->create($derp);
  my $form_from_row = $reflector->reflect_from( $row,  
    { 
      form => 
        { 
          name => 'test' 
        }, 
        with_trigger => 1 
    } 
  );

=back


=head1 INTERNAL METHODS

=head2 $self->field_type_map

Hashref of the supported DBMS type->form element translations.

=cut

=head2 $self->field_class_options

Default options for L<Form::Sensible> field classes.

=cut

=head2 $self->get_base_definition($name, $datatype)

This gets field definitions for a given datatype and returns them in hashref form.

=cut

sub get_base_definition {
    my ( $self, $name, $columninfo ) = @_;
    ## big ass hash for mapping sql->form types
    ## use respective DBMS role, call ->get_types
    my $definition = { 'name' => $name, };

    my $type = $columninfo->{'data_type'};
    if ( !exists( $self->field_type_map->{$type} ) ) {
        $type = 'varchar';
    }
    my $field_type_map = $self->field_type_map->{$type};

    # set up any defaults we might have.  These are values, no mapping here.
    if ( exists( $field_type_map->{'defaults'} ) ) {
        foreach my $parameter ( keys %{ $field_type_map->{'defaults'} } ) {
            $definition->{$parameter} =
              $field_type_map->{'defaults'}{$parameter};
        }
    }

# this loops over the attribute map and brings over any attributes that can be directly
# applied.  This is useful for things like 'size' where the columninfo itself will tell you
# maximum length, etc.  It's also used to find any override parameters provided by the user in the validation
# or render_hints keys in the column info.
    my $attribute_map =
      $self->field_class_options->{ $definition->{'field_class'} } || {};
    if ( exists( $field_type_map->{'attribute_map'} ) ) {
        foreach my $attribute ( keys %{ $field_type_map->{'attribute_map'} } ) {
            $attribute_map->{$attribute} =
              $field_type_map->{'attribute_map'}{$attribute};
        }
    }

    foreach my $attribute ( keys %{$attribute_map} ) {
        my $mappedkey = $attribute_map->{$attribute};

        if ( ref($mappedkey) eq 'HASH' ) {
            my $section = $attribute;
            foreach my $attr ( keys %{$mappedkey} ) {
                if ( exists( $columninfo->{$section}{$attr} ) ) {
                    $definition->{$mappedkey} = $columninfo->{$section}{$attr};
                }
            }
        }
        else {
            if ( exists( $columninfo->{$attribute} ) ) {
                $definition->{$mappedkey} = $columninfo->{$attribute};
            }
        }
    }

    ## now we can add some detailed processing of types here - for example - select processing:

    ## we already allow setting of 'options_delegate' directly, but if we just want to specify the allowed options
    ## we can do it by setting the values in $columninfo->{'validation'}{'options'}
    if ( $definition->{'field_class'} eq 'Select' ) {
        if ( exists( $columninfo->{'validation'}{'options'} ) ) {
            my $options = [ @{ $columninfo->{'validation'}{'options'} } ];
            $definition->{'options_delegate'} = sub {
                return $options;
            };
        }
    }

    return $definition;
}

=head2 $self->get_fieldnames()

Get field names for the form, for example, the column names in the table.

=cut

sub get_fieldnames {
    my ( $self, $form, $handle ) = @_;
    return $self->result_source_for($handle)->columns;
}

=head2 $self->get_field_definition()

Get a given field's definition.

=cut

sub get_field_definition {
    my ( $self, $form, $handle, $name ) = @_;
    ## TODO:
    ## 1. Follow relationships
    ## 2. Options for primary key rendering other than "hidden"

    ## check to see if it's a primary key
    my $result_source = $self->result_source_for($handle);
    my $columninfo    = $result_source->column_info($name);
    my $is_ai         = $columninfo->{is_auto_increment};

    my $definition;

    if ( $columninfo->{fs_select_name_column} ) {
        $columninfo->{fs_select_value_column} ||= $columninfo->{fs_select_name_column};
    }

    if ( $columninfo->{fs_select_value_column} ) {
        $columninfo->{fs_select_name_column} ||= $columninfo->{fs_select_value_column};
    }

    if ( $columninfo->{fs_select_name_column} && $columninfo->{fs_select_value_column} ) {
        $definition->{field_class} = 'Select';

        for ($result_source->relationships) {
            my $relationship_info = $result_source->relationship_info($_);
            my $cond = $relationship_info->{cond};

            if ( grep { $cond->{$_} eq "self.$name" } keys %$cond ) {
                my $fs_select_name_column = $columninfo->{fs_select_name_column};
                my $fs_select_value_column = $columninfo->{fs_select_value_column};

                $relationship_info->{source} =~ /:?(\w+)$/;

                $definition->{options} = [
                    map {
                        {
                            name => $_->$fs_select_name_column,
                            value => $_->$fs_select_value_column,
                        }
                    } $result_source->schema->resultset($1)->all
                ];

                last;
            }
        }
    }
    else {
        $definition = $self->get_base_definition( $name, $columninfo );
    }

    $definition->{'validation'} ||= {};

    ## by default, we obey is_nullable to determine whether the field is required.
    $definition->{'validation'}{required} = ! $columninfo->{'is_nullable'};

    ## these require special handling, as they need to go into the validation subhash
    ## when found.
    foreach my $key (qw/regex required code/) {
        if ( exists( $columninfo->{'validation'}{$key} ) ) {
            $definition->{'validation'}{$key} =
              $columninfo->{'validation'}{$key};
        }
    }

    $definition->{render_hints} = $columninfo->{'render_hints'} || {};

    ## if we have an fs_definition, anything within it overrides what was set earlier.
    ## note that validation (and render_hints) are COMPLETELY OVERWRITTEN by the contents of fs_definition,
    ## no merging of subhashes is done.
    foreach my $key ( keys %{ $columninfo->{'fs_definition'} } ) {
        $definition->{$key} = $columninfo->{'fs_definition'}{$key};
    }

    ## if the column is part of the primary key, we default to hiding it on the form.
    if ( $is_ai && !exists( $columninfo->{render_hints}{field_type} ) )
    {
        $definition->{'render_hints'} = { 'field_type' => 'hidden' };
    }

    ## default value handling?  do we bother here?
    return $definition;
}

sub create_form_object {
    my ( $self, $handle, $form_options ) = @_;

    ## normally create_form_object will throw a fit if you give it no options because
    ## it needs at least a name.  If we get no options, we make up a name based on the resultsource we are looking at.

    my $options = {};
    if ( ref($form_options) eq 'HASH' ) {
        %{$options} = map { $_ => $form_options->{$_} } keys %{$form_options};
    }
    if ( !( exists( $options->{'name'} ) && defined( $options->{'name'} ) ) ) {
        $options->{'name'} =
             $self->source_name
          || $self->result_class
          || $self->name
          || ref($self);
        if ( $options->{'name'} =~ m/([^:]+)$/ ) {
            $options->{'name'} = $1;
        }
        $options->{'name'} =~ s/[^a-zA-Z0-9_]//g;
    }
    return Form::Sensible::Form->new($options);
}

sub result_source_for {
    my ( $self, $handle ) = @_;

    if ( $handle->can('result_source') ) {
        return $handle->result_source();
    }
    else {
        return $handle;
    }
}

__PACKAGE__->meta->make_immutable;
1;

=head1 CONTRIBUTORS

=over 4

=item Devin Austin <devin.austin@gmail.com>

=item Jay Kuri <jayk@cpan.org>

=item Andrew Moore <amoore@cpan.org>

=item Alan Rafagudinov <alan.rafagudinov@ionzero.com>

=back


