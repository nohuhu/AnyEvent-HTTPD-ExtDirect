package AnyEvent::HTTPD::ExtDirect;

use parent 'AnyEvent::HTTPD';

use common::sense;

use IO::File;
use File::Temp;
use File::Basename;

use AnyEvent::HTTPD::Request;

use RPC::ExtDirect::Util::Accessor;
use RPC::ExtDirect::Config;
use RPC::ExtDirect::API;
use RPC::ExtDirect;
use RPC::ExtDirect::Router;
use RPC::ExtDirect::EventProvider;

#
# This module is not compatible with RPC::ExtDirect < 3.0
#

die "AnyEvent::HTTPD::ExtDirect requires RPC::ExtDirect 3.0+"
    if $RPC::ExtDirect::VERSION < 3.0;

### PACKAGE GLOBAL VARIABLE ###
#
# Version of the module
#

our $VERSION = '0.01';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new AnyEvent::HTTPD::ExtDirect object
#

sub new {
    my ($class, %params) = @_;
    
    my $config = delete $params{config} || RPC::ExtDirect::Config->new();
    my $api    = delete $params{api}    || RPC::ExtDirect->get_api();
    
    $config->add_accessors(
        overwrite => 1,
        complex   => [{
            accessor => 'router_class_anyevent',
            fallback => 'router_class',
        }, {
            accessor => 'eventprovider_class_anyevent',
            fallback => 'eventprovider_class',
        }],
    );
    
    my $r_class = delete $params{router_class};
    my $e_class  = delete $params{eventprovider_class};
    
    $config->router_class_anyevent($r_class)        if $r_class;
    $config->eventprovider_class_anyevent($e_class) if $e_class;
    
    # AnyEvent::HTTPD wants IP address
    $params{host} = '127.0.0.1' if $params{host} =~ /localhost/io;

    my $self = $class->SUPER::new(%params);
    
    $self->{config} = $config;
    $self->{api}    = $api;

    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Run the server
#

sub run {
    my ($self) = @_;
    
    my $config      = $self->config;
    
    $self->_set_callbacks(
        api_path    => $config->api_path,
        router_path => $config->router_path,
        poll_path   => $config->poll_path,
    );

    $self->SUPER::run();
}

### PUBLIC INSTANCE METHODS ###
#
# Read-write accessors.
#

RPC::ExtDirect::Util::Accessor::mk_accessors(
    simple => [qw/ api config /],
);

############## PRIVATE METHODS BELOW ##############

### PRIVATE INSTANCE METHOD ###
#
# Register the callbacks for Ext.Direct handlers
#

sub _set_callbacks {
    my ($self, %params) = @_;
    
    my $api_path    = $params{api_path};
    my $router_path = $params{router_path};
    my $poll_path   = $params{poll_path};
    
    $self->reg_cb(
        $api_path    => \&_handle_api,
        $router_path => \&_handle_router,
        $poll_path   => \&_handle_events,
    );
}

### PRIVATE INSTANCE METHOD ###
#
# Handle Ext.Direct API calls
#

sub _handle_api {
    my ($self, $req) = @_;

    # Get the API JavaScript chunk
    my $js = eval {
        $self->api->get_remoting_api( config => $self->config )
    };

    # If JS API call failed, return error
    return $self->_error_response if $@;

    # Content length should be in octets
    my $content_length = do { use bytes; my $len = length $js };

    $req->respond([
        200,
        'OK',
        {
            'Content-Type'   => 'application/javascript',
            'Content-Length' => $content_length,
        },
        $js
    ]);

    $self->stop_request;
}

### PRIVATE INSTANCE METHOD ###
#
# Handle Ext.Direct method requests
#

sub _handle_router {
    my ($self, $req) = @_;
    
    if ( $req->method ne 'POST' ) {
        $req->respond( $self->_error_response );
        $self->stop_request;
        
        return;
    }
    
    my $config = $self->config;
    my $api    = $self->api;

    # Naked AnyEvent::HTTPD::Request object doesn't provide several
    # utility methods we'll need down below, and we will need it as
    # an environment object, too
    my $env = bless $req, __PACKAGE__.'::Env';

    # We're trying to distinguish between a raw POST and a form call
    my $router_input = $self->_extract_post_data($env);

    # If the extraction fails, undef is returned by the method above
    if ( !defined $router_input ) {
        $req->respond( $self->_error_response );
        $self->stop_request;

        return;
    }
    
    my $router_class = $config->router_class_anyevent;
    
    eval "require $router_class";
    
    my $router = $router_class->new(
        config => $config,
        api    => $api,
    );

    # No need for eval here, Router won't throw exceptions
    my $result = $router->route($router_input, $env);

    # Router result is Plack-compatible arrayref; there's not much
    # difference in what AnyEvent::HTTPD expects so we just convert it
    # directly
    $req->respond([
        200,
        'OK',
        +{ @{ $result->[1] } },
        $result->[2]->[0],
    ]);
    
    $self->stop_request;
}

### PRIVATE INSTANCE METHOD ###
#
# Polls Event handlers for events, returning serialized stream
#

sub _handle_events {
    my ($self, $req) = @_;
    
    # Only GET and POST methods are supported for polling
    my $method = $req->method;
    
    if ( $method ne 'GET' && $method ne 'POST' ) {
        $req->respond( $self->_error_response );
        $self->stop_request;
        
        return;
    }
    
    my $config = $self->config;
    my $api    = $self->api;
    
    my $env = bless $req, __PACKAGE__.'::Env';
    
    my $provider_class = $config->eventprovider_class_anyevent;
    
    eval "require $provider_class";
    
    my $provider = $provider_class->new(
        config => $config,
        api    => $api,
    );
    
    # Polling for Events is safe from exceptions
    my $http_body = $provider->poll($env);
    
    my $content_length
        = do { no warnings 'void'; use bytes; length $http_body };
    
    $req->respond([
        200,
        'OK',
        {
            'Content-Type'   => 'application/json; charset=utf8',
            'Content-Length' => $content_length,
        },
        $http_body,
    ]);
    
    $self->stop_request;
}

### PRIVATE INSTANCE METHOD ###
#
# Deals with intricacies of POST-fu and returns something suitable to
# feed to Router (string or hashref, really). Or undef if something
# goes too wrong to recover.
#
# This code is mostly copied from the Plack interface and adapted
# for AnyEvent::HTTPD.
#

sub _extract_post_data {
    my ($self, $req) = @_;

    # The smartest way to tell if a form was submitted that *I* know of
    # is to look for 'extAction' and 'extMethod' keywords in form params.
    my $is_form = $req->param('extAction') && $req->param('extMethod');

    # If form is not involved, it's easy: just return raw POST (or undef)
    if ( !$is_form ) {
        my $postdata = $req->content;
        return $postdata ne '' ? $postdata
               :                 undef
               ;
    };

    # If any files are attached, extUpload field will be set to 'true'
    my $has_uploads = $req->param('extUpload') eq 'true';

    # Outgoing hash
    my %keyword;

    # Pluck all parameters from the Request object
    for my $param ( $req->params ) {
        my @values = $req->param($param);
        $keyword{ $param } = @values == 0 ? undef
                           : @values == 1 ? $values[0]
                           :                [ @values ]
                           ;
    };

    # Find all file uploads
    for ( $has_uploads ? ($has_uploads) : () ) {
        # The list of fields that contain file uploads
        my @upload_fields = $req->upload_fields;
        
        last unless @upload_fields;
        
        my @uploaded_files;
        
        for my $field_name ( @upload_fields ) {
            my $uploads = $req->raw_param($field_name);

            # We need files as a formatted list
            my @field_uploads = map { $self->_format_upload($_) } @$uploads;
            push @uploaded_files, @field_uploads;

            # Now remove the field that contained files
            delete @keyword{ $field_name };
        }

        $keyword{ '_uploads' } = \@uploaded_files if @uploaded_files;
    };

    # Remove extType because it's meaningless later on
    delete $keyword{ extType };

    # Fix TID so that it comes as number (JavaScript is picky)
    $keyword{ extTID } += 0 if exists $keyword{ extTID };

    return \%keyword;
}

### PRIVATE INSTANCE METHOD ###
#
# Take the file content and metadata and format it in a way
# that RPC::ExtDirect handlers expect
#

sub _format_upload {
    my ($self, $upload) = @_;
    
    my $content_length = do { use bytes; length $upload->[0] };
    
    my ($fh, $fname) = File::Temp::tempfile;
    
    binmode $fh;
    syswrite $fh, $upload->[0], $content_length;
    
    sysseek $fh, 0, 0;
    
    # We don't need the file content anymore, so try to release
    # the memory it takes
    $upload->[0] = undef;
    
    my $filename = $upload->[2];
    my $basename = File::Basename::basename($filename);
    my $type     = $upload->[1];
    my $handle   = IO::File->new_from_fd($fh->fileno, '<');

    return {
        filename => $filename,
        basename => $basename,
        type     => $type,
        size     => $content_length,
        path     => $fname,
        handle   => $handle,
    };
}

### PRIVATE INSTANCE METHOD ###
#
# Return an error response formatted to AnyEvent::HTTPD likes
#

sub _error_response {
    [ 500, 'Internal Server Error', { 'Content-Type' => 'text/html' }, '' ]
}

package
    AnyEvent::HTTPD::ExtDirect::Env;

use parent 'AnyEvent::HTTPD::Request';

#
# AnyEvent::HTTPD::Request stores the form parameters in a peculiar format:
# $self->{parm} is a hashref of arrayrefs; each arrayref contain one
# or more values, again in arrayrefs with fixed number of items: 
# [ content, content-type, file-name ]
#
# For anything but file uploads, the last 2 elements are undef; for the
# file uploads they're the file MIME type and name, respectively.
#
# A dump might look like this:
#
# $self->{parm}:
# 0 HASH
#   'formFieldName' => ARRAY
#       0 ARRAY =>
#           0 'form field value'
#           1 undef
#           2 undef
#   'fieldWithMultipleValues' => ARRAY # SURMISED!
#       0 ARRAY =>
#           0 'form field value 0'
#           1 undef
#           2 undef
#       1 ARRAY =>
#           0 'form field value 1'
#           1 undef
#           2 undef
#   'fileUploads' => ARRAY
#       0 ARRAY =>
#           0 'first file content (all of it!)'
#           1 'first file MIME type'
#           2 'first file name'
#       1 ARRAY =>
#           0 'second file content'
#           1 'second file MIME type'
#           2 'second file name'
# 
# There is no method that returns multiple values for a non-file field,
# and no method that returns file upload parameters, so we have to
# roll our own
#

sub param {
    my ($self, $key) = @_;
    
    return $self->params unless defined $key;
    
    # [] is to avoid autovivification biting my ass ;)
    my @values = map { $_->[0] } @{ $self->{parm}->{$key} || [] };
    
    return wantarray ? @values : shift @values;
}

# Go over the fields and return the list of names for the fields
# that contain file uploads
sub upload_fields {
    my ($self) = @_;
    
    my @upload_fields;
    
    my $params = $self->{parm};
    
    FIELD:
    for my $field_name ( keys %$params ) {
        my $values = $params->{ $field_name };
        
        for my $value ( @$values ) {
            
            # We surmise that for a file upload, at least MIME type
            # should be defined (name is optional)
            if ( defined $value->[1] ) {
                push @upload_fields, $field_name;
                next FIELD;
            }
        }
    }
    
    return @upload_fields;
}

sub raw_param {
    my ($self, $key) = @_;
    
    return $self->{parm}->{$key};
}

sub cookie {
    my ($self, $key) = @_;

    my %cookies;

    if ( $self->{_cookies} ) {
        %cookies = %{ $self->{_cookies} };
    }
    else {
        my $headers    = $self->headers;
        my $cookie_hdr = $headers ? $headers->{cookie} : '';
        %cookies    = map { split /=/, $_ } split /;\s+/, $cookie_hdr;
        $self->{_cookies} = \%cookies;
    }

    return $key ? $cookies{ $key } : keys %cookies;
}

sub http {
    my ($self, $key) = @_;

    my $headers = $self->headers || {};

    return $key ? $headers->{ lc $key } : keys %$headers;
}

1;

