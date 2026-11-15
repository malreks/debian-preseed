package APTRepoLocal::Servicing::HTTP;

use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

use Moo;
use MooX::StrictConstructor;
use lib '__INSTALLER_PATH_DIR_PERL5_SITE_PERL__/runtime';

use APTRepoLocal::Servicing::Atomic;

sub _host {
    my ($self, $url) = @_;
    defined($url) && !ref($url) && length($url) <= 2048 && $url !~ /[\x00-\x20\x7f]/
        or die "URL contains unsupported syntax\n";
    $url =~ m{\Ahttps://([^/?#:]+)(?::443)?(?:/|\z)}
        or die "URL is not a valid HTTPS URL\n";
    my $host = lc $1;
    $host =~ /\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/
        or die "URL contains an invalid host\n";
    return $host;
}

sub _validate_url {
    my ($self, $url) = @_;
    $self->_host($url);
}

sub download {
    my ($self, %args) = @_;
    require Managed::Process;
    for my $key (qw(label url destination content_policy)) {
        exists $args{$key} or die "missing HTTP download parameter $key\n";
    }
    $args{content_policy} =~ /\A(?:artifact|metadata|signature)\z/
        or die "unsupported HTTP content policy\n";
    !exists($args{response_metadata}) || ref($args{response_metadata}) eq 'HASH'
        or die "invalid HTTP response metadata destination\n";
    my $user_agent = $args{user_agent} // 'debian-installer-software/2.0';
    $user_agent =~ /\A[A-Za-z0-9][A-Za-z0-9 ._+\/-]{0,127}\z/
        or die "invalid HTTP user agent\n";
    APTRepoLocal::Servicing::Atomic->assert_absolute_path('download destination', $args{destination});
    my %allowed_hosts;
    if (exists $args{allowed_hosts}) {
        ref($args{allowed_hosts}) eq 'ARRAY' && @{$args{allowed_hosts}} >= 1
            && @{$args{allowed_hosts}} <= 16 or die "invalid HTTP host policy\n";
        for my $host (@{$args{allowed_hosts}}) {
            defined($host) && !ref($host)
                && $host =~ /\A[a-z0-9]+(?:[.-][a-z0-9]+)*\z/
                && !$allowed_hosts{$host}++ or die "invalid HTTP allowed host\n";
        }
    }
    my $validate = sub {
        my ($candidate) = @_;
        $self->_validate_url($candidate);
        my $host = $self->_host($candidate);
        !%allowed_hosts || $allowed_hosts{$host}
            or die "HTTP destination is outside the selected artifact host policy\n";
    };
    $validate->($args{url});

    my $partial = "$args{destination}.part";
    unlink $partial if -e $partial || -l $partial;
    my $url = $args{url};
    my ($status, $effective, $content_type);
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + 900;
    my $ok = eval {
        for my $hop (0 .. 8) {
            # curl never follows a redirect itself. Validate every resolved next
            # URL before contacting it, including intermediate and same-host hops.
            $validate->($url);
            my $remaining = int($deadline - clock_gettime(CLOCK_MONOTONIC));
            $remaining > 0 or die "HTTP operation deadline exhausted\n";
            my @command = (
                '__INSTALLER_PATH_DIR_USR__/bin/curl', '--disable', '--fail', '--silent', '--show-error',
                '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15',
                '--max-redirs', '0', '--max-time', $remaining, '--speed-limit', '1024', '--speed-time', '45',
                '--retry', '3', '--retry-max-time', $remaining, '--retry-delay', '2',
                '--retry-all-errors',
                '--user-agent', $user_agent,
                '--header', 'Accept: application/octet-stream, application/vnd.debian.binary-package;q=0.9, */*;q=0.1',
                '--output', $partial, '--write-out', "%{http_code}\n%{url_effective}\n%{content_type}\n%{redirect_url}",
                '--url', $url,
            );
            # Keep a bounded 15-second connection establishment check plus the
            # reviewed HTTPS, redirect, retry and partial-file checks.
            # The same deadline covers every retry, redirect and final wait.
            my $result = Managed::Process::capture_command(
                argv => \@command, timeout => $remaining, limit => 16384,
                progress => sub {
                    my @st = lstat $partial;
                    return q{} if !@st && $!{ENOENT};
                    @st && -f _ && !-l _ or die "unsafe HTTP partial file\n";
                    return "$st[0]:$st[1]:$st[7]";
                },
            );
            if ($result->{status} != 0) {
                my $reason = ($result->{error} // q{}) eq 'timeout'
                    ? 'transfer made no progress through its retry window'
                    : ($result->{status} & 127)
                        ? 'curl terminated by signal ' . ($result->{status} & 127)
                        : 'curl transport error (exit ' . ($result->{status} >> 8) . ')';
                die "$args{label} download failed: $reason\n";
            }
            my $next;
            ($status, $effective, $content_type, $next) = split /\n/, $result->{stdout}, 4;
            defined($effective) or die "$args{label} effective URL is invalid\n";
            $validate->($effective);
            if (defined($status) && $status =~ /\A(?:301|302|303|307|308)\z/) {
                $hop < 8 && defined($next) && length($next)
                    or die "$args{label} redirect limit or invalid redirect\n";
                $validate->($next);
                $url = $next;
                next;
            }
            last;
        }
        defined $status && $status eq '200' or die "$args{label} download returned an unexpected HTTP status\n";
        defined $effective && length($effective) <= 2048 or die "$args{label} effective URL is invalid\n";
        $validate->($effective);
        $content_type //= q{};
        $content_type = lc((split /;/, $content_type, 2)[0]);
        if ($args{content_policy} eq 'artifact') {
            $content_type !~ /\A(?:text\/(?:html|plain|xml)|application\/(?:json|xml))\z/
                or die "$args{label} download returned a non-artifact content type\n";
        } elsif ($args{content_policy} eq 'signature') {
            $content_type =~ /\A(?:application\/(?:pgp-keys|pgp-signature|octet-stream)|text\/plain)\z/
                or die "$args{label} download returned an unsupported signature content type\n";
        } elsif ($content_type ne q{} && $content_type !~ /\A(?:application\/(?:octet-stream|vnd\.github\+json|json|yaml|x-yaml)|text\/(?:plain|yaml|x-yaml)|binary\/octet-stream)\z/) {
            die "$args{label} download returned an unsupported metadata content type\n";
        }
        -f $partial && !-l $partial or die "$args{label} download is not a regular file\n";
        rename $partial, $args{destination} or die "failed to publish downloaded $args{label}: $!\n";
        if (exists $args{response_metadata}) {
            %{$args{response_metadata}} = (status => $status, effective_url => $effective,
                                         content_type => $content_type);
        }
        1;
    };
    my $error = $@;
    if (!$ok) {
        unlink $partial if -e $partial || -l $partial;
        die $error || "$args{label} download failed\n";
    }
    return $args{destination};
}

1;
