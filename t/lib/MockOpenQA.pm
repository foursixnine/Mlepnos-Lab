package MockOpenQA;
use strict;
use warnings;
use Mojo::JSON qw(encode_json decode_json);
use Mojolicious::Lite;
use IO::Socket::INET;
use File::Temp qw(tempfile tempdir);
use POSIX qw(:sys_wait_h);
use Exporter 'import';
our @EXPORT_OK = qw(start_mock_server stop_mock_server mock_base_url);

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

    # prepare request log file
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
        # child process: run Mojolicious::Lite app
        app->secrets(["mocksecret"]);

        my $requests = [];

        get '/api/v1/machines' => sub {
            my $c = shift;
            push @$requests, {method => 'GET', path => '/api/v1/machines'};
            open my $of, '>', $REQ_FILE;
            print $of encode_json($requests);
            close $of;
            $c->render(json => {Machines => [ {id => 111, name => 'mock-machine', backend => 'qemu'} ]});
        };

        post '/api/v1/machines' => sub {
            my $c = shift;
            my $body = $c->req->body;
            push @$requests, {method => 'POST', path => '/api/v1/machines', body => $body, headers => $c->req->headers->to_hash};
            open my $of, '>', $REQ_FILE;
            print $of encode_json($requests);
            close $of;
            $c->render(json => {id => 222});
        };

        post '/api/v1/job_templates_scheduling' => sub {
            my $c = shift;
            my $body = $c->req->body;
            push @$requests, {method => 'POST', path => '/api/v1/job_templates_scheduling', body => $body};
            open my $of, '>', $REQ_FILE;
            print $of encode_json($requests);
            close $of;
            $c->render(json => {result => 1});
        };

        get '/__requests' => sub {
            my $c = shift;
            $c->render_file(filepath => $REQ_FILE, format => 'json');
        };

        # start daemon
        my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://127.0.0.1:$PORT"]);
        $daemon->start;
        exit 0;
    }

    # parent
    $CHILD_PID = $pid;
    # wait briefly for server to start
    sleep 0.2;
    return ($CHILD_PID, $PORT, $REQ_FILE);
}

sub mock_base_url { return "http://127.0.0.1:$PORT" }

sub stop_mock_server {
    return unless $CHILD_PID;
    kill 'TERM', $CHILD_PID;
    waitpid($CHILD_PID, 0);
    $CHILD_PID = undef;
    $PORT = undef;
    $REQ_FILE = undef;
}

1;
