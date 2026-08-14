package MockOpenQA;
use strict;
use warnings;
use Mojo::JSON qw(encode_json decode_json);
use Mojolicious::Lite;
use IO::Socket::INET;
use File::Temp qw(tempfile);
use Exporter 'import';
our @EXPORT_OK = qw(start_mock_server stop_mock_server mock_base_url req_file_path);

my ($CHILD_PID, $PORT, $REQ_FILE);

sub _choose_port {
    my $sock = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp')
      or die "cannot get free port: $!";
    my $port = $sock->sockport;
    close $sock;
    return $port;
}

sub start_mock_server {
    my ($port, $req_file) = @_;
    die "mock server already running" if $CHILD_PID;
    $PORT = $port || _choose_port();

    if ($req_file) {
        $REQ_FILE = $req_file;
    }
    else {
        my ($fh, $fn) = tempfile();
        close $fh;
        $REQ_FILE = $fn;
    }

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        app->secrets(["mocksecret"]);

        # Mutable in-memory store for products
        my %products = (
            201 => { id => 201, distri => 'mockdistri', version => '16.0', arch => 'x86_64', flavor => 'default', description => 'mock', settings => [ { key => 'VERSION', value => '16.0' } ] }
        );
        my $next_product_id = 202;

        my $requests = [];

        # Helper to persist request log
        my $write_log = sub {
            open my $of, '>', $REQ_FILE or die "cannot write req file: $!";
            print $of encode_json($requests);
            close $of;
        };

        # Products
        get '/api/v1/products' => sub {
            my $c = shift;
            push @$requests, {method => 'GET', path => '/api/v1/products'};
            $write_log->();
            my @list = map { $products{$_} } sort { $a <=> $b } keys %products;
            $c->render(json => { Products => \\@list });
        };

        get '/api/v1/products/:id' => sub {
            my $c = shift;
            my $id = $c->param('id');
            push @$requests, {method => 'GET', path => "/api/v1/products/$id"};
            $write_log->();
            if ($products{$id}) {
                $c->render(json => { product => $products{$id} });
            }
            else {
                $c->render(json => { error => 'Not found' }, status => 404);
            }
        };

        post '/api/v1/products' => sub {
            my $c = shift;
            my $body = $c->req->body || '';
            my $data = eval { decode_json($body) } || {};
            push @$requests, {method => 'POST', path => '/api/v1/products', body => $body, headers => $c->req->headers->to_hash};
            my $id = $next_product_id++;
            $data->{id} = $id;
            $data->{settings} ||= [];
            $products{$id} = $data;
            $write_log->();
            $c->render(json => { id => $id });
        };

        put '/api/v1/products/:id' => sub {
            my $c = shift;
            my $id = $c->param('id');
            my $body = $c->req->body || '';
            my $data = eval { decode_json($body) } || {};
            push @$requests, {method => 'PUT', path => "/api/v1/products/$id", body => $body, headers => $c->req->headers->to_hash};
            # Merge fields into existing product
            if ($products{$id}) {
                for my $k (keys %$data) {
                    $products{$id}{$k} = $data->{$k};
                }
                # Normalize settings if provided as hash
                if (ref $data->{settings} eq 'HASH') {
                    my @s = map { { key => $_, value => $data->{settings}{$_} } } keys %{$data->{settings}};
                    $products{$id}{settings} = \@s;
                }
                $write_log->();
                $c->render(json => { result => 1 });
            }
            else {
                $write_log->();
                $c->render(json => { error => 'Not found' }, status => 404);
            }
        };

        delete('/api/v1/products/:id' => sub {
            my $c = shift;
            my $id = $c->param('id');
            push @$requests, {method => 'DELETE', path => "/api/v1/products/$id"};
            CORE::delete $products{$id};
            $write_log->();
            $c->render(json => { result => 1 });
        });

        # Machines (minimal; static responses)
        my %machines = (111 => { id => 111, name => 'mock-machine', backend => 'qemu' });
        get '/api/v1/machines' => sub {
            push @$requests, {method => 'GET', path => '/api/v1/machines'};
            $write_log->();
            $c->render(json => { Machines => [ values %machines ] });
        };

        post '/api/v1/machines' => sub {
            my $c = shift;
            push @$requests, {method => 'POST', path => '/api/v1/machines', body => $c->req->body, headers => $c->req->headers->to_hash};
            $write_log->();
            $c->render(json => { id => 222 });
        };

        # TestSuites minimal
        get '/api/v1/test_suites' => sub {
            push @$requests, {method => 'GET', path => '/api/v1/test_suites'};
            $write_log->();
            $c->render(json => { TestSuites => [ { id => 301, name => 'mock-ts', description => 'mock' } ] });
        };

        post '/api/v1/test_suites' => sub {
            push @$requests, {method => 'POST', path => '/api/v1/test_suites', body => $c->req->body};
            $write_log->();
            $c->render(json => { id => 302 });
        };

        # Job templates scheduling endpoint (form)
        post '/api/v1/job_templates_scheduling' => sub {
            my $c = shift;
            push @$requests, {method => 'POST', path => '/api/v1/job_templates_scheduling', body => $c->req->body};
            $write_log->();
            $c->render(json => { result => 1 });
        };

        # Job templates minimal
        get '/api/v1/job_templates' => sub {
            push @$requests, {method => 'GET', path => '/api/v1/job_templates'};
            $write_log->();
            $c->render(json => { JobTemplates => [] });
        };

        post '/api/v1/job_templates' => sub {
            push @$requests, {method => 'POST', path => '/api/v1/job_templates', body => $c->req->body};
            $write_log->();
            $c->render(json => { result => 1 });
        };

        # test-only endpoint to fetch recorded requests
        get '/__requests' => sub {
            my $c = shift;
            $c->render_file(filepath => $REQ_FILE, format => 'json');
        };

        my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://127.0.0.1:$PORT"]);
        $daemon->start;
        exit 0;
    }

    $CHILD_PID = $pid;
    sleep 0.2;
    return ($CHILD_PID, $PORT, $REQ_FILE);
}

sub mock_base_url { return "http://127.0.0.1:$PORT" }
sub req_file_path { return $REQ_FILE }

sub stop_mock_server {
    return unless $CHILD_PID;
    kill 'TERM', $CHILD_PID;
    waitpid($CHILD_PID, 0);
    $CHILD_PID = undef;
    $PORT = undef;
    $REQ_FILE = undef;
}

1;
