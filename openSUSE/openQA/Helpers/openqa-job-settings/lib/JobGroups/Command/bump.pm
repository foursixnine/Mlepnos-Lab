package JobGroups::Command::bump;
use Mojo::Base 'Mojolicious::Command', -signatures;
use Mojo::JSON qw(encode_json decode_json);

## Dinamically load OpenQA::Client
use lib "/usr/share/openqa/lib";
use Mojo::Loader qw(load_class);

use Getopt::Long qw(GetOptionsFromArray);
use Mojo::URL;
use Utils qw(debug);
use Storable qw(dclone);

has description => 'Manage products across openQA instances (match/set/create/delete)';
has usage => sub {
    "Usage: jobgroups-cli bump [--host HOST] [--apikey KEY] [--apisecret SECRET]\n"
      . "                      [--target-host [HOST]] [--target-apikey KEY] [--target-apisecret SECRET]\n"
      . "                      [--match key=value] [--set key=value] [--delete-target]\n"
      . "                      [--dry-run] [--no-dry-run --yes] [--retries N]\n\n"
      . "Examples:\n"
      . "  # Dry-run: find VERSION=16.0 and show what would be created on target\n"
      . "  jobgroups-cli bump --host http://src --target-host http://tgt --match VERSION=16.0 --set VERSION=16.1 --set MYVAR=%ARCH%\n\n"
      . "Defaults: dry-run (no writes). Pass --no-dry-run --yes to perform updates.\n";
};

has opts => sub { {} };

# Build a target client similar to OpenQA::Command->client behaviour
sub _make_client_for_host ($self, $host) {
    debug "Preparing Client for $host";
    #TODO; Die if host doesn't have protocol set
    die("host must be not empty got: $host") unless $host;

    my %opts = %{$self->opts};
    my $base   = Mojo::URL->new($host);                         # full host URL with scheme
    my $client_class = ($opts{client_class})? $opts{client_class} : 'OpenQA::Client';
    my %client_args = map { $_ => $opts{$_} } grep { defined $opts{$_} } qw(apikey apisecret);
    $client_args{api} = $base->host;

    # Mojo::Loader::load_class returns false on success, or an error/exception on failure
    if (my $e = load_class($client_class)) {
        die "Cannot load client class $client_class: " . (ref $e ? $e : 'Module not found');
    }

    my $c = $client_class->new(%client_args);
    $c->base_url($base)->ioloop(Mojo::IOLoop->singleton);
    $c->transactor->name('jobgroups-cli') if $c->can('transactor');

    debug "Client for $host set", $c->base_url->to_string;

    return $c;
}

# Convert API-style settings array -> hash and ensure payload is a HASH with settings as a HASH ref.
sub _normalize_product_for_api ($self, $product) {
    return unless $product && ref $product eq 'HASH';

    # If settings is an array of {key,value} entries, normalize to a key->value hash
    if (ref $product->{settings} eq 'ARRAY') {
        my %settings_hash;
        for my $entry (@{ $product->{settings} }) {
            if (ref $entry eq 'HASH' && exists $entry->{key}) {
                $settings_hash{ $entry->{key} } = $entry->{value};
            }
        }
        $product->{settings} = \%settings_hash;
    }

    # If settings absent, ensure it's at least an empty hashref to match API expectations
    if (!defined $product->{settings} || ref $product->{settings} ne 'HASH') {
        $product->{settings} = {} unless defined $product->{settings};
        # if it was non-hash and not an array (unexpected), leave it alone to avoid data loss,
        # but prefer hash for API consumption:
        $product->{settings} = {} unless ref $product->{settings} eq 'HASH';
    }

    return $product;
}

# Helper: Extracts all defined values for $key across all locations in $product
sub _get_product_values ($self, $product, $key) {
    my @found;

    # 1. Top-level scalar
    if (exists $product->{$key} && !ref $product->{$key}) {
        push @found, $product->{$key} if defined $product->{$key};
    }

    # 2. Nested containers
    for my $container (qw(settings variables attributes)) {
        next unless exists $product->{$container};

        # Nested Hash: { settings => { key => value } }
        if (ref $product->{$container} eq 'HASH' && exists $product->{$container}{$key}) {
            my $val = $product->{$container}{$key};
            push @found, $val if defined $val;
        }
        # Nested Array of Hashes: { settings => [ { key => '...', value => '...' } ] }
        elsif (ref $product->{$container} eq 'ARRAY') {
            for my $entry (@{ $product->{$container} }) {
                if (ref $entry eq 'HASH' 
                    && ($entry->{key} // '') eq $key 
                    && defined $entry->{value}) 
                {
                    push @found, $entry->{value};
                }
            }
        }
    }

    return @found;
}

# match product top-level or in the common nested keys
sub _product_matches ($self, $product, $filters) {
    for my $filter (@$filters) {
        my $op     = lc($filter->{op} // 'or');
        my $key    = $filter->{key};
        my @wants  = @{ $filter->{values} // [] };

        my @actuals = $self->_get_product_values($product, $key);
        # debug "_product_matches", {actuals => @actuals, key => $key, wants => \@wants, op => $op, product => $product};
        # OPERATOR: OR / IN / EQ (Product value matches ANY specified value)
        if ($op eq 'or' || $op eq 'in' || $op eq 'eq') {
            my %want_set = map { $_ => 1 } @wants;
            my $matched  = 0;
            for my $act (@actuals) {
                if ($want_set{$act}) {
                    $matched = 1;
                    last;
                }
            }
            return 0 unless $matched;
        }
        # OPERATOR: AND (Product values contain ALL specified values)
        elsif ($op eq 'and') {
            my %actual_set = map { $_ => 1 } @actuals;
            for my $w (@wants) {
                return 0 unless $actual_set{$w};
            }
        }
        # OPERATOR: NOT / NE (Product value matches NONE of specified values)
        elsif ($op eq 'not' || $op eq 'ne') {
            my %want_set = map { $_ => 1 } @wants;
            for my $act (@actuals) {
                return 0 if $want_set{$act};
            }
        }
    }

    return 1;
}

# apply set criteria (key => value) to product (top-level or nested destination); returns number of changes
sub _apply_set_criteria ($self, $product, $set_criteria) {
    my $changes = 0;
    for my $k (keys %$set_criteria) {
        my $val = $set_criteria->{$k};
        # prefer to set in existing nested container if key exists there, otherwise set in settings
        my $placed = 0;
        for my $container (qw(settings variables attributes)) {
            if (ref $product->{$container} eq 'HASH' && exists $product->{$container}{$k}) {
                $product->{$container}{$k} = $val;
                $placed = 1;
                last;
            }
            # if settings is an array (source format), update existing entry in that array
            if ($container eq 'settings' && ref $product->{settings} eq 'ARRAY') {
                for my $entry (@{ $product->{settings} }) {
                    if (ref $entry eq 'HASH' && $entry->{key} && $entry->{key} eq $k) {
                        $entry->{value} = $val;
                        $placed = 1;
                        last;
                    }
                }
                last if $placed;
            }
        }
        unless ($placed) {
            # put into settings hash if exists, else create settings hash
            if (!ref $product->{settings}) { $product->{settings} = {} }
            if (ref $product->{settings} eq 'HASH') {
                $product->{settings}{$k} = $val;
            }
            else {
                # fallback: set as top-level if settings is a strange structure
                $product->{$k} = $val;
            }
        }
        $changes++;
    }
    return $changes;
}

sub run ($self, @args) {
    # detect presence of bare --target-host in args (no value) to treat it as intent to target localhost
    my $target_host_flag_present = 0;
    for (my $i = 0; $i < @args; $i++) {
        my $a = $args[$i];
        if ($a eq '--target-host' || $a =~ /^--target-host=/) {
            $target_host_flag_present = 1;
            last;
        }
    }

    my %openqa_client = ( verbose => 0, pretty => 1, quiet => 1 );

   my %opts = (
        host              => undef,
        apikey            => undef,
        apisecret         => undef,
        target_host       => undef,
        target_apikey     => undef,
        target_apisecret  => undef,
        match             => [],
        set               => [],
        delete_target     => 1,
        dry_run           => 1,
        yes               => 0,
        retries           => undef,
        debug             => undef,
        filters            => []
    );


    my @raw_filters;
    GetOptionsFromArray(
        \@args,
        'o3!'    => \$opts{o3},
        'host=s'               => \$opts{host},
        'apikey=s'             => \$opts{apikey},
        'apisecret=s'          => \$opts{apisecret},
        'target-host:s'        => \$opts{target_host},
        'target-apikey=s'      => \$opts{target_apikey},
        'target-apisecret=s'   => \$opts{target_apisecret},
        'match=s@'             => \$opts{match},
        'set=s@'               => \$opts{set},
        'delete-target!'       => \$opts{delete_target},
        'dry-run!'             => \$opts{dry_run},
        'yes|y'                => \$opts{yes},
        'retries=i'            => \$opts{retries},
        'debug'                => \$opts{debug},
        'openqa-client-verbose!' => \$openqa_client{verbose},
        'openqa-client-pretty!' => \$openqa_client{pretty},
        'openqa-client-quiet!' => \$openqa_client{quiet},
        'filter=s{3}' => \@raw_filters,
    ) or die $self->usage;

    # Clean post-processing loop
    while (@raw_filters) {
        my ($op, $key, $val_str) = splice(@raw_filters, 0, 3);
        push @{ $opts{filters} }, {
            op     => lc($op),
            key    => $key,
            values => [ split /,/, $val_str ],
        };
    }   
    
    $self->opts(\%opts);
    # undef %opts;

    local $Utils::Debug = 1 if $opts{debug};
    if (!$opts{yes} && !$opts{dry_run}) {
        $opts{dry_run} = 1;
        debug "No yes detected, this is a forced dry run", {options => $self->opts};
    }

    $opts{host} = "https://openqa.opensuse.org" if $opts{o3};
    if ($opts{o3} && !defined $opts{target_host}) {
        $opts{target_host} = 'http://localhost';
    }

    my $src_host = $opts{host} // $ENV{OPENQA_HOST} // 'http://localhost';
    $src_host = "http://$src_host" if $src_host !~ m{^https?://};

    my $src_client = $self->_make_client_for_host($src_host);

    my $tgt_host = (defined $opts{target_host} && $opts{target_host} ne '') ? $opts{target_host} : die("'--target-host host' must be set");
    $tgt_host = "http://$tgt_host" if $tgt_host !~ m{^https?://};

    my $tgt_client;
    if ($tgt_host ne $src_host) {
        $tgt_client = $self->_make_client_for_host($tgt_host);
    } else {
        $tgt_client = $src_client;
    }

    debug "Source $src_host";
    debug "Target $tgt_host";
    debug "Source host: ", {api => $src_client->{api}, base_url => $src_client->base_url->to_string};
    debug "Target host: ", {api => $tgt_client->{api}, base_url => $tgt_client->base_url->to_string};
    debug "Dry run mode (no writes) enabled" if $opts{dry_run} && !$opts{yes};
    debug "Finished setting up the clients";

    my $products_url = sub ($client){ return Mojo::URL->new('/api/v1/products')->to_abs($client->base_url) };
    my $tx = $src_client->build_tx(GET => $products_url->($src_client));
    my $rc = $src_client->start($tx);

    if ($rc->res->code ne 200) {
        debug "Source Server Response", $rc->res;
    }

    my $json = $tx->res->json // {};
    my $products = $json->{products} // $json->{Products} // $json;
    $products = [$products] unless ref $products eq 'ARRAY';

    my %match_criteria;
    for my $m (@{$opts{match}}) {
        if ($m =~ /^([^=]+)=(.*)$/s) { $match_criteria{lc $1} = $2 }
    }
    my %set_criteria;
    for my $s (@{$opts{set}}) {
        if ($s =~ /^([^=]+)=(.*)$/s) { $set_criteria{lc $1} = $2 }
    }

    my @candidates = grep { $self->_product_matches($_, $self->opts->{filters}) } @$products;
    debug scalar(@candidates) . " product(s) matched criteria";
    debug scalar(@$products) . " Total product(s)";

    if (scalar(@candidates) == 0){
        debug "No products matched", {filters => \@{$self->opts->{filters}}, candidates => \@candidates};
    } else {
        # TODO: ask the user to confirm changes
        debug "Candidates", {candidates => \@candidates};
    }

    my @created_on_target;
    my @deleted_on_target;
    for my $p (@candidates) {
        my $new = dclone($p);

        delete $new->{id};
        delete $new->{product_id} if exists $new->{product_id};

        my $changed = $self->_apply_set_criteria($new, \%set_criteria);
        debug "Prepared new product (changes applied: $changed)";

        # Normalize for API: convert settings array -> hash, ensure hashref
        $self->_normalize_product_for_api($new);

        my $new_product_name = qq{$new->{distri}-$new->{version}-$new->{flavor}-$new->{arch}};
        my $old_product_name = qq{$p->{distri}-$p->{version}-$p->{flavor}-$p->{arch}};
        debug "Preview for new product: ", { new => $new_product_name, old => $old_product_name, changed => $changed };

        if (!$opts{dry_run} && $opts{yes}) {
            my $create_url = Mojo::URL->new('/api/v1/products')->to_abs($tgt_client->base_url);
            my $tx2 = $tgt_client->build_tx(POST => $create_url => json => $new);

            # debug "transaction ready", { url => $create_url->to_string };

            # $tgt_client->on(start => sub {
            #     debug "Starting transaction $create_url";
            # });

            my $rc2 = $tgt_client->start($tx2);
            if ($rc2->res->code == 200) {
                my $res2 = $rc2->res;
                my $created = $res2->json;
                $created->{name} = $new_product_name;
                push @created_on_target, $created;
                debug "Product created on target (response): ", $created;
            }
            else {
                debug "Failed to create product on target", { wanted => $new, txn => $tx2->res->json, server_response => $rc2->res->json};
            }
        }
    }

    if ($opts{delete_target} && @created_on_target) {
        debug "before deleting", {creeated_on_target => \@created_on_target};
        for my $created (@created_on_target) {
            my $tid = $created->{id};
            my $name = $created->{name};
            unless ($tid) {
                debug "Cannot delete created $name - no id present in response: ", { created => $created};
                next;
            }
            my $del_url = Mojo::URL->new("/api/v1/products/$tid")->to_abs($tgt_client->base_url);
            debug "Deleting created product on target: $del_url";
                my $txd = $tgt_client->build_tx(DELETE => $del_url);
                my $rcd = $tgt_client->start($txd);

                if ($rcd->res->code == 200) {
                    my $res = $rcd->res;
                    my $deleted = $res->json // {};
                    push @deleted_on_target, $deleted;
                    debug "Deleted created on target (response): ", {deleted => $deleted};
                }
                else {
                    # debug "Failed to delete product on target", { server_response => $rcd->res->json };
                    debug "Failed to delete $tid", { txn => $txd->res->json, server_response => $rcd->res->json};
                }
        }

        if (scalar(@created_on_target) == scalar(@deleted_on_target)){
            debug "All records have been properly deleted";
        }
    }

    debug "Source host: ", {api => $src_client->{api}, base_url => $src_client->base_url->to_string};
    debug "Target host: ", {api => $tgt_client->{api}, base_url => $tgt_client->base_url->to_string};
    debug "Dry run mode (no writes) enabled" if $opts{dry_run} && !$opts{yes};
    debug "This is a dry run (use '--yes --no-dry-run' to write)" if $opts{dry_run};
    debug "Records will be deleted after creation (use '--no-delete-target' to make them permanent)" if $opts{delete_target};
    debug "Created ". scalar @created_on_target ." records on target host" if !$opts{delete_target} && $opts{yes};

    return 0;
}

1;
