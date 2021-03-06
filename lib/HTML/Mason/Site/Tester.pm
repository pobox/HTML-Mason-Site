package HTML::Mason::Site::Tester;

use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use HTML::Mason::Site;
use HTML::Mason::Site::FakeApacheHandler;

use HTTP::Request;
use HTTP::Request::AsCGI;

use IO::File;

__PACKAGE__->mk_accessors(qw(site));

=head1 NAME

HTML::Mason::Site::Tester

=head1 SYNOPSIS

  use HTML::Mason::Site::Tester;
  my $tester = HTML::Mason::Site::Tester->new(...);
  my $response = $tester->request("/foo");

=head1 DESCRIPTION

HTML::Mason::Site::Tester objects make it easier to test Mason
applications.  Each tester object is tied to a
HTML::Mason::Site object, and makes requests to it without
needing an external webserver.

=head1 METHODS

=head2 new

  my $tester = HTML::Mason::Site::Tester->new(...);

Create a new tester object associated with a particular site.

The first (mandatory) argument is a hashref which is passed
into HTML::Mason::Site-E<gt>new.

=head2 request

  my $response = $tester->request('/foo?bar=1');

Make a request for the given path.  Returns a HTTP::Response object.

=head2 request_ascgi

  my $as_cgi = $tester->request_ascgi($request);

Returns a HTTP::Request::AsCGI object for the given HTTP::Request.  Override
this in subclasses.

=head2 get

  my $content = $tester->get('/foo?bar=1');

Make a request for the given path, and return the content.

=head2 url_base

=head2 default_url_base

See L<Test::WWW::Mechanize::Object|Test::WWW::Mechanize::Object>.

Uses the C<MASON_SERVER> environment variable to do remote
requests on demand.

=cut

sub url_base { $ENV{MASON_SERVER} || shift->default_url_base }

sub default_url_base { "http://localhost.localdomain" }

sub new {
  my $class = shift;
  my $site_config = shift;
  my $site = HTML::Mason::Site->new($site_config);
  $site->set_handler('HTML::Mason::Site::FakeApacheHandler');
  $site->require_modules;

  return bless {
    site    => $site,
  } => $class;
}

sub _request_from_url {
  my ($self, $url) = @_;
  $url = $self->url_base . $url if $url =~ m!^/!;
  return HTTP::Request->new( GET => $url );
}

sub request_ascgi {
  my $self = shift;
  return HTTP::Request::AsCGI->new(@_);
}

sub _local_request {
  my ($self, $request) = @_;
  my $uri = $request->uri;
  $uri->path($self->{site}->rewrite_path($uri->path));

  my $c = $self->request_ascgi($request);
  $c->stderr(IO::File->new_tmpfile)
    unless $ENV{HTML_MASON_SITE_TESTER_DEBUG};
  $c->setup;
  $self->{site}->handler->handle_request;
  $c->restore;

  my $response = $c->response;
  
  $response->header('Content-Base' => $request->uri);

  return $response;
}

my $agent;
sub _remote_request {
  my ($self, $request) = @_;
  require LWP::UserAgent;
  unless ($agent) {
    $agent = LWP::UserAgent->new(
      keep_alive   => 1,
      max_redirect => 0,
      timeout      => 60,
    );
    $agent->env_proxy;
  }

  # XXX this should be moved into TWMO
  my $server = URI->new( $ENV{MASON_SERVER} );
  $request->uri->scheme( $server->scheme );
  $request->uri->host  ( $server->host );
  $request->uri->port  ( $server->port );
  $request->uri->path  ( $server->path . $request->uri->path );

  return $agent->request($request);
}

sub request {
  my ($self, $request) = @_;
  $request = $self->_request_from_url($request)
    unless eval { $request->isa('HTTP::Request') };

  return $ENV{MASON_SERVER} ?
    $self->_remote_request($request) :
      $self->_local_request($request);
}

1;
