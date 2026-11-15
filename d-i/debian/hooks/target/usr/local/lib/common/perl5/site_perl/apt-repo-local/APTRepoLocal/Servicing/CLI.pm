package APTRepoLocal::Servicing::CLI;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;
use JSON::PP qw(decode_json);

use APTRepoLocal::Servicing::Bitwarden;
use APTRepoLocal::Servicing::ChatGPT;
use APTRepoLocal::Servicing::Deb;
use APTRepoLocal::Servicing::Discord;
use APTRepoLocal::Servicing::Event;
use APTRepoLocal::Servicing::HTTP;
use APTRepoLocal::Servicing::Logger qw(log_msg);
use APTRepoLocal::Servicing::Notifier;
use APTRepoLocal::Servicing::Obsidian;
use APTRepoLocal::Servicing::Process;
use APTRepoLocal::Servicing::Repository;
use APTRepoLocal::Servicing::Sleek;
use APTRepoLocal::Servicing::Tomat;
use APTRepoLocal::Servicing::State;
use APTRepoLocal::Servicing::Atomic;

my $SOFTWARE_RELEASE_POLICY_PATH = '__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/software/software-release-policy.json';

sub _software_release_policy {
    my ($self) = @_;
    return $self->{software_release_policy}
        if exists $self->{software_release_policy};

    my $raw = eval {
        APTRepoLocal::Servicing::Atomic->read_limited(
            $SOFTWARE_RELEASE_POLICY_PATH,
            65_536,
        );
    };
    $@ and die "managed software release policy could not be read\n";

    my $policy = eval { decode_json($raw) };
    $@ and die "managed software release policy is not valid JSON\n";
    ref($policy) eq 'HASH'
        && defined($policy->{schema})
        && $policy->{schema} =~ /\A1\z/
        && ref($policy->{generic_deb}) eq 'HASH'
        && ref($policy->{service_urls}) eq 'HASH'
        && ref($policy->{metadata_limits}) eq 'HASH'
        && ref($policy->{postman}) eq 'HASH'
        && ref($policy->{discord}) eq 'HASH'
        && ref($policy->{ledger}) eq 'HASH'
        or die "managed software release policy has an invalid schema\n";

    my %validated;
    my %generic_deb;
    for my $name (qw(bitwarden zoom filen chatgpt)) {
        my $entry = $policy->{generic_deb}{$name};
        ref($entry) eq 'HASH'
            && defined($entry->{url})
            && $entry->{url} =~ /\Ahttps:\/\/[^\s"\\]+\z/
            or die "managed software release policy entry is invalid: $name\n";
        $generic_deb{$name} = {
            url           => $entry->{url},
        };
    }

    my %service_urls;
    for my $name (qw(
        chatgpt discord_manifest qoredb_discovery obsidian_discovery postman sleek_discovery
        tomat_discovery tuta_appimage tuta_signature
    )) {
        my $url = $policy->{service_urls}{$name};
        defined($url) && $url =~ /\Ahttps:\/\/[^\s"\\]+\z/
            or die "managed software service URL is invalid: $name\n";
        $service_urls{$name} = $url;
    }

    my %metadata_limits;
    # This bounds the JSON parser, independently of transfer size.
    for my $name (qw(maximum_bytes)) {
        my $value = $policy->{metadata_limits}{$name};
        defined($value)
            && $value =~ /\A[1-9][0-9]*\z/
            or die "managed software metadata limit is invalid: $name\n";
        $metadata_limits{$name} = 0 + $value;
    }

    my %postman_limits;
    for my $name (qw(maximum_extracted_bytes maximum_members metadata_maximum_bytes)) {
        my $value = $policy->{postman}{$name};
        defined($value)
            && $value =~ /\A[1-9][0-9]*\z/
            or die "managed Postman limit is invalid: $name\n";
        $postman_limits{$name} = 0 + $value;
    }

    my %discord_limits;
    for my $name (qw(
        host_tar_maximum_bytes module_tar_maximum_bytes
        host_maximum_members module_maximum_members tree_maximum_files tree_maximum_bytes
        tree_reserved_files tree_reserved_bytes
    )) {
        my $value = $policy->{discord}{$name};
        defined($value)
            && $value =~ /\A[1-9][0-9]*\z/
            or die "managed Discord limit is invalid: $name\n";
        $discord_limits{$name} = 0 + $value;
    }
    $discord_limits{tree_reserved_files} < $discord_limits{tree_maximum_files}
        && $discord_limits{tree_reserved_bytes} < $discord_limits{tree_maximum_bytes}
        or die "managed Discord limits are inconsistent\n";
    $discord_limits{manifest_url} = $service_urls{discord_manifest};

    my $ledger = $policy->{ledger};
    for my $name (qw(requested_latest_url metadata_url checksums_base_url)) {
        defined($ledger->{$name})
            && $ledger->{$name} =~ /\Ahttps:\/\/[^\s"\\]+\z/
            or die "managed Ledger release policy URL is invalid: $name\n";
    }
    $ledger->{checksums_base_url} =~ /-\z/
        or die "managed Ledger checksum URL base is invalid\n";
    defined($ledger->{public_key_sha256})
        && $ledger->{public_key_sha256} =~ /\A[0-9a-f]{64}\z/
        or die "managed Ledger public key fingerprint is invalid\n";
    my %ledger_limits;
    for my $name (qw(
        appimage_maximum_extracted_bytes appimage_maximum_members
    )) {
        defined($ledger->{$name})
            && $ledger->{$name} =~ /\A[1-9][0-9]*\z/
            or die "managed Ledger release policy limit is invalid: $name\n";
        $ledger_limits{$name} = 0 + $ledger->{$name};
    }
    $validated{ledger} = {
        requested_latest_url => $ledger->{requested_latest_url},
        metadata_url        => $ledger->{metadata_url},
        checksums_base_url  => $ledger->{checksums_base_url},
        public_key_sha256   => $ledger->{public_key_sha256},
        %ledger_limits,
    };
    $validated{generic_deb} = \%generic_deb;
    $validated{service_urls} = \%service_urls;
    $validated{metadata_limits} = \%metadata_limits;
    $validated{postman} = \%postman_limits;
    $validated{discord} = \%discord_limits;

    $self->{software_release_policy} = \%validated;
    return $self->{software_release_policy};
}

sub _log {
    my ($self, $level, $message) = @_;
    print STDERR "[apt-repo-local-software-update] $level: $message\n";
    log_msg($level, $message);
}

sub _clear_apply_failure_detail {
    my ($self) = @_;
    delete $self->{apply_failure_detail};
    return 1;
}

sub _record_apply_failure_detail {
    my ($self, $stage, $detail) = @_;
    defined $stage && $stage =~ /\A[a-z][a-z0-9-]{0,31}\z/
        or die "managed package failure stage is invalid\n";
    $detail = 'unknown failure' if !defined $detail || $detail eq q{};
    $detail =~ s/[\r\n\t]+/ /g;
    $detail =~ s/[\x00-\x1f\x7f]/?/g;
    $detail =~ s/\s+/ /g;
    $detail =~ s/\A\s+|\s+\z//g;
    $detail = substr($detail, 0, 1024);
    $self->{apply_failure_detail} = "$stage: $detail";
    $self->_log('warning', $self->{apply_failure_detail});
    return 1;
}

sub apply_failure_detail {
    my ($self) = @_;
    return $self->{apply_failure_detail};
}

sub _version_compare {
    my ($self, $left, $operator, $right) = @_;
    my $result = system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--compare-versions', $left, $operator, $right);
    return 1 if $result == 0;
    return 0 if $result == 256;
    die "managed package version comparison failed\n";
}

sub _application_update_blocker {
    my ($self, $app) = @_;
    my @executables = (
        $app->{executable},
        @{$app->{in_use_executables} // []},
    );
    my $running = eval {
        APTRepoLocal::Servicing::Process->application_running(
            executables => \@executables,
            roots       => $app->{in_use_roots} // [],
        );
    };
    if ($@) {
        $self->_record_apply_failure_detail('process-check', $@);
        return 'validation';
    }
    if ($running) {
        $self->_record_apply_failure_detail(
            'in-use',
            "$app->{label} is running; its retained update was not installed",
        );
        return 'in-use';
    }
    return undef;
}

sub _payload_is_present {
    my ($self, $deb, $app, $chatgpt) = @_;
    return 0 if !$deb->installed_payload_valid($app);
    return APTRepoLocal::Servicing::Bitwarden->new()->policy_valid()
        if $app->{name} eq 'bitwarden';
    return 1 if $app->{name} ne 'chatgpt';
    return 0 if !$deb->installed_dependencies_allowed(
        $app->{packages}[0],
        $app->{remove_dependencies},
    );
    return $chatgpt->policy_valid();
}

sub _generic_deb_specs {
    my ($self, $chatgpt) = @_;
    my $release_policy = $self->_software_release_policy();
    my @specs = (
        {
            name       => 'bitwarden',
            label      => 'Bitwarden Desktop',
            url        => $release_policy->{generic_deb}{bitwarden}{url},
            packages   => ['bitwarden'],
            executable => '__INSTALLER_PATH_DIR_OPT__/Bitwarden/bitwarden',
            in_use_roots => ['__INSTALLER_PATH_DIR_OPT__/Bitwarden'],
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/bitwarden.desktop',
            library    => '__INSTALLER_PATH_DIR_OPT__/Bitwarden/libffmpeg.so',
            sandbox    => '__INSTALLER_PATH_DIR_OPT__/Bitwarden/chrome-sandbox',
            sandbox_presence => 'required',
            required_paths => ['__INSTALLER_PATH_DIR_OPT__/Bitwarden/resources/app.asar'],
            required_executables => ['__INSTALLER_PATH_DIR_OPT__/Bitwarden/desktop_proxy'],
        },
        {
            name       => 'zoom',
            label      => 'Zoom Workplace',
            url        => $release_policy->{generic_deb}{zoom}{url},
            packages   => ['zoom'],
            executable => '__INSTALLER_PATH_DIR_USR__/bin/zoom',
            in_use_roots => ['__INSTALLER_PATH_DIR_OPT__/zoom'],
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/Zoom.desktop',
            library    => q{},
        },
        {
            name       => 'filen',
            label      => 'Filen Desktop',
            url        => $release_policy->{generic_deb}{filen}{url},
            packages   => [qw(filen filen-desktop)],
            executable => '__INSTALLER_PATH_DIR_OPT__/Filen/Filen',
            in_use_roots => ['__INSTALLER_PATH_DIR_OPT__/Filen'],
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/Filen.desktop',
            library    => '__INSTALLER_PATH_DIR_OPT__/Filen/libffmpeg.so',
            sandbox    => '__INSTALLER_PATH_DIR_OPT__/Filen/chrome-sandbox',
            sandbox_presence => 'optional',
        },
    );
    push @specs, $chatgpt->spec() if $chatgpt->enabled();
    return @specs;
}

sub _release_deb_specs {
    return (
        {
            name       => 'obsidian',
            label      => 'Obsidian',
            packages   => ['obsidian'],
            executable => '__INSTALLER_PATH_DIR_OPT__/Obsidian/obsidian',
            in_use_roots => ['__INSTALLER_PATH_DIR_OPT__/Obsidian'],
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/md.obsidian.Obsidian.desktop',
            library    => '__INSTALLER_PATH_DIR_OPT__/Obsidian/libffmpeg.so',
        },
        {
            name       => 'sleek',
            label      => 'Sleek',
            packages   => ['sleek'],
            executable => '__INSTALLER_PATH_DIR_OPT__/sleek/sleek',
            in_use_roots => ['__INSTALLER_PATH_DIR_OPT__/sleek'],
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/sleek.desktop',
            library    => '__INSTALLER_PATH_DIR_OPT__/sleek/libffmpeg.so',
        },
        {
            name       => 'tomat',
            label      => 'Tomat',
            packages   => ['tomat'],
            executable => '__INSTALLER_PATH_DIR_USR__/bin/tomat',
            in_use_roots => ['__INSTALLER_PATH_DIR_USR__/bin/tomat'],
            desktop    => q{},
            required_executables => ['__INSTALLER_PATH_DIR_USR__/bin/tomat'],
        },
    );
}

sub _pinned_deb_specs {
    return (
        {
            name       => 'qoredb',
            label      => 'QoreDB',
            packages   => ['qore-db'],
            executable => '__INSTALLER_PATH_DIR_USR__/bin/qoredb',
            desktop    => '__INSTALLER_PATH_DIR_USR_SHARE__/applications/QoreDB.desktop',
            library    => q{},
        },
    );
}

sub _all_deb_specs {
    my ($self, $chatgpt) = @_;
    return (
        $self->_generic_deb_specs($chatgpt),
        $self->_release_deb_specs(),
        $self->_pinned_deb_specs(),
    );
}

sub _stage_deb {
    my ($self, $deb, $event, $repository, $app, $path, $metadata) = @_;
    ref $metadata eq 'HASH'
        && defined $metadata->{package} && defined $metadata->{version}
        or die "$app->{label} artifact metadata is invalid\n";
    my $installed = $deb->installed_version($metadata->{package});
    if (defined $installed) {
        return (2, 'current')
            if $self->_version_compare($metadata->{version}, 'lt', $installed);
    }
    my ($retained_path, $created);
    my $retained = eval {
        ($retained_path, $created) = $repository->retain($path, $metadata);
        defined $retained_path && defined $created
            or die "managed repository retention returned no result\n";
        1;
    };
    if (!$retained) {
        my $detail = $@ || 'managed repository retention returned no result';
        $self->_record_apply_failure_detail('repository', $detail);
        return (1, 'validation');
    }
    if ($created) {
        $event->emit('downloaded', $app->{name}, $installed // 'not-installed', $metadata->{version});
        return (0, 'downloaded');
    }
    return (2, 'current');
}

sub _fetch_generic_deb {
    my ($self, $http, $deb, $event, $repository, $work, $app) = @_;
    my $path = "$work/$app->{name}.deb";
    $self->_clear_apply_failure_detail();
    my $stage = 'download';
    my $metadata = eval {
        $http->download(
            label          => $app->{label},
            url            => $app->{url},
            destination    => $path,
            content_policy => 'artifact',
        );
        $stage = 'source-metadata';
        my $metadata = $deb->validate_spec($path, $app, $app->{label});
        # The repository applies its persisted package policy before publishing;
        # retain the original download so later policy changes can be reapplied.
        $metadata;
    };
    if (!$metadata) {
        my $detail = $@ || 'package download returned no metadata';
        $self->_record_apply_failure_detail($stage, $detail);
        return (1, $detail =~ /download|HTTP|URL/i ? 'download' : 'validation');
    }
    return $self->_stage_deb($deb, $event, $repository, $app, $path, $metadata);
}

sub _fetch_release_deb {
    my ($self, $module, $deb, $event, $repository, $work, $app) = @_;
    my $release = eval { $module->download($work) };
    return (1, $@ =~ /download|HTTP|URL/i ? 'download' : 'validation') if !$release;
    ref $release eq 'HASH' && defined $release->{path} && ref $release->{metadata} eq 'HASH'
        or return (1, 'validation');
    return $self->_stage_deb(
        $deb,
        $event,
        $repository,
        $app,
        $release->{path},
        $release->{metadata},
    );
}

sub _apply_deb {
    my ($self, $deb, $event, $repository, $app, $chatgpt, $execution_context) = @_;
    $execution_context //= 'runtime';
    $self->_clear_apply_failure_detail();
    my $candidate = eval { $repository->latest($deb, $app) };
    if ($@) {
        $self->_record_apply_failure_detail('candidate', $@);
        return (1, 'validation');
    }
    return (2, 'current') if !defined $candidate;

    my $metadata = $candidate->{metadata};
    my $vendor_receipt;
    my $vendor_installed = 1;
    if ($app->{name} eq 'bitwarden') {
        $vendor_receipt = $repository->directory() . '/bitwarden.installed-vendor.sha256';
        $vendor_installed = eval { $repository->bitwarden_vendor_digest_matches(
            $vendor_receipt, $candidate->{vendor_sha256},
        ) };
        if ($@) {
            $self->_record_apply_failure_detail('vendor-receipt', $@);
            return (1, 'validation');
        }
    }
    my $installed = $deb->installed_version($metadata->{package});
    my $reinstall = 0;
    if (defined $installed) {
        my $candidate_is_older = $self->_version_compare(
            $metadata->{version},
            'lt',
            $installed,
        );
        my $candidate_is_equal = $self->_version_compare(
            $metadata->{version},
            'eq',
            $installed,
        );
        if (($candidate_is_older || $candidate_is_equal)
            && $app->{name} eq 'chatgpt'
            && $deb->installed_payload_valid($app)
            && $deb->installed_dependencies_allowed(
                $app->{packages}[0],
                $app->{remove_dependencies},
            )) {
            my $blocked = $self->_application_update_blocker($app);
            return (1, $blocked) if defined $blocked;
            my $finalized = eval {
                $chatgpt->finalize_install($execution_context);
                $chatgpt->commit_install();
                1;
            };
            if (!$finalized) {
                my $detail = $@ || 'policy finalization returned no result';
                my $cleanup = eval {
                    $chatgpt->abort_install();
                    1;
                };
                if (!$cleanup) {
                    my $cleanup_error = $@ || 'guard cleanup returned no result';
                    $detail .= " cleanup failure: $cleanup_error";
                }
                $self->_record_apply_failure_detail(
                    'finalize',
                    $detail,
                );
                return (1, 'policy');
            }
            return (2, 'current');
        }
        if ($candidate_is_older) {
            return (2, 'current') if $self->_payload_is_present(
                $deb,
                $app,
                $chatgpt,
            );
            return (1, 'payload');
        }
        if ($candidate_is_equal) {
            if ($vendor_installed && $self->_payload_is_present($deb, $app, $chatgpt)) {
                return (2, 'current');
            }
            $reinstall = 1;
        }
    }
    my $blocked = $self->_application_update_blocker($app);
    return (1, $blocked) if defined $blocked;
    $event->emit('applying', $app->{name}, $installed // 'not-installed', $metadata->{version});
    my $stage = $app->{name} eq 'chatgpt' ? 'prepare' : 'apt';
    my $applied = eval {
        $chatgpt->prepare_install($execution_context) if $app->{name} eq 'chatgpt';
        $stage = 'apt';
        if ($app->{name} eq 'chatgpt') {
            $chatgpt->package_install(sub { $deb->install($candidate->{path}, $reinstall) });
        } else {
            $deb->install($candidate->{path}, $reinstall);
        }
        $stage = 'sandbox';
        $deb->repair_chromium_sandbox($app->{sandbox}, $app->{sandbox_presence})
            if defined $app->{sandbox} && $app->{sandbox} ne q{};
        $stage = 'finalize';
        $chatgpt->finalize_install($execution_context) if $app->{name} eq 'chatgpt';
        1;
    };
    if (!$applied) {
        my $detail = $@ || 'package transaction returned no result';
        if ($app->{name} eq 'chatgpt') {
            my $cleanup = eval {
                $chatgpt->abort_install();
                1;
            };
            if (!$cleanup) {
                my $cleanup_error = $@ || 'guard cleanup returned no result';
                $detail .= " cleanup failure: $cleanup_error";
            }
        }
        $self->_record_apply_failure_detail($stage, $detail);
        return (1, ($stage eq 'prepare' || $stage eq 'finalize') ? 'policy' : 'install');
    }
    my $verified = $deb->installed_version($metadata->{package});
    if (!defined $verified
        || $verified ne $metadata->{version}
        || !$self->_payload_is_present($deb, $app, $chatgpt)) {
        $self->_record_apply_failure_detail(
            'verify',
            'installed package version, payload, or managed policy verification failed',
        );
        $chatgpt->abort_install() if $app->{name} eq 'chatgpt';
        return (1, 'postinstall');
    }
    $chatgpt->commit_install() if $app->{name} eq 'chatgpt';
    if (defined $vendor_receipt) {
        my $recorded = eval {
            APTRepoLocal::Servicing::Atomic->write_text(
                $vendor_receipt, "$candidate->{vendor_sha256}\n", 0644,
            );
            1;
        };
        if (!$recorded) {
            $self->_record_apply_failure_detail('vendor-receipt', $@);
            return (1, 'postinstall');
        }
    }
    $event->emit('updated', $app->{name}, $installed // 'not-installed', $metadata->{version});
    return (0, 'updated');
}

sub _record_result {
    my ($self, $event, $application, $result, $reason, $success_ref, $failed_ref) = @_;
    if ($result == 0) {
        $$success_ref++;
        return;
    }
    return if $result == 2;
    $$failed_ref++;
    $event->emit('failed', $application, $reason, '-');
    $self->_log('warning', "$application $reason");
}

sub _run_repair {
    my ($self, $state, $event, $work) = @_;
    my $repository = APTRepoLocal::Servicing::Repository->new(directory => $state->deb_dir());
    my $deb = APTRepoLocal::Servicing::Deb->new(repository => $repository);
    my $release_policy = $self->_software_release_policy();
    my $chatgpt = APTRepoLocal::Servicing::ChatGPT->new(
        state => $state,
        release_policy => $release_policy,
    );
    my $failed = 0;
    for my $app ($self->_all_deb_specs($chatgpt)) {
        my $repaired = eval {
            if ($app->{name} eq 'chatgpt') {
                if (defined $deb->installed_version($app->{packages}->[0])
                    && $deb->installed_payload_valid($app)
                    && $deb->installed_dependencies_allowed(
                        $app->{packages}[0],
                        $app->{remove_dependencies},
                    )) {
                    my $blocked = $self->_application_update_blocker($app);
                    if (defined $blocked) {
                        0;
                    } else {
                        $chatgpt->finalize_install('runtime');
                        $chatgpt->commit_install();
                        1;
                    }
                } else {
                    my ($result, $reason) = $self->_apply_deb(
                        $deb,
                        $event,
                        $repository,
                        $app,
                        $chatgpt,
                    );
                    $result == 0
                        || ($result == 2
                            && $self->_payload_is_present(
                                $deb,
                                $app,
                                $chatgpt,
                            ))
                        ? 1
                        : 0;
                }
            } elsif ($app->{name} eq 'bitwarden') {
                my ($result, $reason) = $self->_apply_deb(
                    $deb,
                    $event,
                    $repository,
                    $app,
                    $chatgpt,
                );
                $result == 0
                    || ($result == 2
                        && $self->_payload_is_present(
                            $deb,
                            $app,
                            $chatgpt,
                        ))
                    ? 1
                    : 0;
            } else {
                $repository->repair($deb, $app);
            }
        };
        if (!$repaired) {
            $failed = 1;
            $self->_log('warning', "$app->{name} offline repair failed");
        }
    }
    my $http = APTRepoLocal::Servicing::HTTP->new();
    my $discord = APTRepoLocal::Servicing::Discord->new(
        http  => $http,
        event => $event,
        state => $state,
        release_policy => $release_policy->{discord},
    );
    my ($discord_result, $discord_reason) = eval { $discord->repair($work) };
    ($discord_result, $discord_reason) = (1, 'validation')
        if $@ || !defined $discord_result;
    if ($discord_result == 1) {
        $failed = 1;
        $event->emit('failed', 'discord', $discord_reason, '-');
        $self->_log('warning', "discord offline repair failed: $discord_reason");
    }
    $self->_log($failed ? 'warning' : 'info', $failed
        ? 'one or more managed applications could not be repaired offline'
        : 'managed application offline repair completed');
    return $failed ? 1 : 0;
}

sub _run_bootstrap_chatgpt {
    my ($self, $state, $event, $work) = @_;
    my $release_policy = $self->_software_release_policy();
    my $chatgpt = APTRepoLocal::Servicing::ChatGPT->new(
        state => $state,
        release_policy => $release_policy,
    );
    $chatgpt->enabled()
        or die "ChatGPT bootstrap requires a selected desktop medium/full class receipt\n";
    my $http = APTRepoLocal::Servicing::HTTP->new();
    my $repository = APTRepoLocal::Servicing::Repository->new(directory => $state->deb_dir());
    my $deb = APTRepoLocal::Servicing::Deb->new(repository => $repository);
    my $app = $chatgpt->spec();

    my ($download_result, $download_reason) = $self->_fetch_generic_deb(
        $http,
        $deb,
        $event,
        $repository,
        $work,
        $app,
    );
    if ($download_result == 1) {
        my $detail = $self->apply_failure_detail();
        my $suffix = defined $detail && $detail ne q{}
            ? " ($detail)"
            : q{};
        my $phase = defined($detail) && $detail =~ /\Arepository:/
            ? 'repository import'
            : $download_reason eq 'download' ? 'download' : 'package validation';
        die "ChatGPT bootstrap $phase failed: $download_reason$suffix\n";
    }

    my ($apply_result, $apply_reason) = $self->_apply_deb(
        $deb,
        $event,
        $repository,
        $app,
        $chatgpt,
        'installer',
    );
    if ($apply_result == 1) {
        my $detail = $self->apply_failure_detail();
        my $suffix = defined $detail && $detail ne q{}
            ? " ($detail)"
            : q{};
        die "ChatGPT bootstrap installation failed: $apply_reason$suffix\n";
    }
    return 0;
}

sub run_updater {
    my ($self, @argv) = @_;
    @argv <= 1
        && (!@argv || $argv[0] =~ /\A--(?:download-only|apply-only|repair-only|bootstrap-discord|bootstrap-chatgpt)\z/)
        or die "usage: apt-repo-local-software-update [--download-only|--apply-only|--repair-only|--bootstrap-discord|--bootstrap-chatgpt]\n";
    $> == 0
        or die "this updater must run as root\n";
    open my $arch_fh, '-|', '__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--print-architecture'
        or die "dpkg is unavailable\n";
    my $architecture = <$arch_fh> // q{};
    close $arch_fh
        or die "dpkg architecture query failed\n";
    chomp $architecture;
    $architecture eq 'amd64'
        or die "managed external software updates are supported only on amd64\n";

    # Retired scheduled entry points can only refresh the catalogue. They must
    # never install software behind APT or acquire its locks from an update hook.
    if (!@argv || $argv[0] eq '--download-only' || $argv[0] eq '--apply-only') {
        exec '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/apt-repo-local', 'refresh'
            or die "cannot execute local APT repository refresh: $!\n";
    }
    my $mode = $argv[0];
    my $state = APTRepoLocal::Servicing::State->new();
    $state->prepare();
    my $lock = $state->lock();
    if (!defined $lock) {
        $self->_log('info', 'another managed external software action is already running');
        return 0;
    }
    my $work = $state->work_dir();
    my $event = APTRepoLocal::Servicing::Event->new(directory => $state->event_dir());
    my $result = eval {
        if ($mode eq '--repair-only') {
            $self->_run_repair($state, $event, $work);
        } elsif ($mode eq '--bootstrap-chatgpt') {
            $self->_run_bootstrap_chatgpt($state, $event, $work);
        } elsif ($mode eq '--bootstrap-discord') {
            my $http = APTRepoLocal::Servicing::HTTP->new();
            my $discord = APTRepoLocal::Servicing::Discord->new(
                http  => $http,
                event => $event,
                state => $state,
                release_policy => $self->_software_release_policy()->{discord},
            );
            my ($discord_result, $discord_reason) = $discord->bootstrap($work);
            if ($discord_result != 0) {
                my $detail = $discord->failure_detail();
                my $suffix = defined $detail && $detail ne q{}
                    ? " ($detail)"
                    : q{};
                die "Discord bootstrap failed: $discord_reason$suffix\n";
            }
            0;
        } else {
            die "unsupported updater operation\n";
        }
    };
    my $error = $@;
    $state->cleanup_work_dir($work);
    die $error if $error;
    return $result;
}

sub run_notifier {
    my ($self, @argv) = @_;
    @argv == 0
        or die "usage: apt-repo-local-software-notify\n";
    return APTRepoLocal::Servicing::Notifier->new()->run();
}

1;
