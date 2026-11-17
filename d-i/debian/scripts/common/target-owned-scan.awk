# Data-only target scan. Run by d-i, never by a target or development host.
# Input rows: target path, authenticated source member, kind, phase, mode.
function fatal(message) {
    print "fatal: " message
    failed = 1
}
function source_has(list, member, count, i, parts) {
    count = split(list, parts, ",")
    for (i = 1; i <= count; i++) if (parts[i] == member) return 1
    return 0
}
BEGIN {
    FS = "\t"
    while ((status = getline row < registry) > 0) {
        if (row ~ /^format\t/) {
            if (row !~ /^format\t2\t/) { fatal("unsupported placeholder ownership registry"); exit 2 }
            format_seen++
            continue
        }
        if (row ~ /^token\t/) continue
        count = split(row, fields, "\t")
        if (count != 19 || fields[1] in namespace) {
            fatal("malformed placeholder ownership registry phase=finish-install")
            exit 2
        }
        token = fields[1]
        namespace[token] = fields[3]
        owner[token] = fields[5] ":" fields[6]
        sources[token] = fields[18]
        absent[token] = fields[16]
        literal_sources[token] = fields[19] == "-" ? "" : fields[19]
    }
    close(registry)
    if (status < 0 || format_seen != 1) {
        fatal("cannot read placeholder ownership registry phase=finish-install")
        exit 2
    }
}
{
    if (NF != 5 || $1 !~ /^\// || seen[$1]++ || ++members > 10000) {
        fatal("malformed or excessive target ownership inventory phase=finish-install")
        next
    }
    destination = $1; source = $2; kind = $3; phase = $4
    file = target_root destination
    offset = 0; line_number = 0
    while ((read_status = getline line < file) > 0) {
        line_number++
        bytes += length(line) + 1
        if (bytes > 268435456) {
            fatal("project-owned target scan exceeds aggregate byte limit phase=finish-install")
            exit 2
        }
        rest = line; consumed = 0
        # Identifier segments cannot absorb a closing delimiter or an adjacent
        # token. The same exact grammar is used by the shared renderers.
        while (match(rest, /__[A-Za-z0-9][A-Za-z0-9.:+-]*(_[A-Za-z0-9.:+-]+)*__/)) {
            token = substr(rest, RSTART, RLENGTH)
            token_offset = offset + consumed + RSTART - 1
            allowed = 0
            if (source_has(sources[token], source)) {
                if (namespace[token] == "APPLICATION_GRAMMAR" && absent[token] == "false") allowed = 1
                if (source_has(literal_sources[token], source) &&
                    (source !~ /fields\.json\.tmpl$/ || kind == "appearance-registry")) allowed = 1
            }
            if (!allowed) {
                if (!(token in namespace)) {
                    printf "fatal: unknown target marker file=%s line=%d offset=%d token=%s owner=unknown source=%s phase=%s\n", destination, line_number, token_offset, token, source, phase
                } else {
                    printf "fatal: unresolved target marker file=%s line=%d offset=%d token=%s owner=%s source=%s phase=%s\n", destination, line_number, token_offset, token, owner[token], source, phase
                }
                failed = 1
            }
            consumed += RSTART + RLENGTH - 1
            rest = substr(rest, RSTART + RLENGTH)
        }
        probe = line; probe_offset = 0
        while ((opening = index(probe, "__INSTALLER_")) > 0) {
            suffix = substr(probe, opening + 2)
            closing = index(suffix, "__")
            marker = closing ? substr(suffix, 1, closing - 1) : suffix
            if (marker ~ /^INSTALLER_[A-Za-z0-9_]/ &&
                (!closing || marker !~ /^INSTALLER_[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/)) {
                printf "fatal: malformed installer marker file=%s line=%d offset=%d owner=unknown source=%s phase=%s\n", destination, line_number, offset + probe_offset + opening - 1, source, phase
                failed = 1
            }
            # A bare prefix in renderer code is data; it cannot give an
            # adjacent named marker an allowance or hide a later failure.
            probe_offset += opening + 10
            probe = substr(probe, opening + 11)
        }
        if (line ~ /(^|[^A-Za-z0-9_])(TARGET_ROOT|INSTALLER_TARGET_DIR|DIR_INSTALLER_[A-Z0-9_]*|FILE_INSTALLER_[A-Z0-9_]*|DIR_REPO_[A-Z0-9_]*|DIR_HOOKS_[A-Z0-9_]*|DIR_SCRIPTS_[A-Z0-9_]*|DIR_HOSTS_[A-Z0-9_]*|FILE_HOOKS_[A-Z0-9_]*|FILE_COMMON_[A-Z0-9_]*)[[:space:]]*=/ || destination ~ /\/(repo|di)\.env$/) {
            printf "fatal: installer environment or repository selector in target file=%s line=%d offset=%d owner=installer-environment source=%s phase=%s\n", destination, line_number, offset, source, phase
            failed = 1
        }
        offset += length(line) + 1
    }
    close(file)
    if (read_status < 0) fatal("cannot read owned target file=" destination " source=" source " phase=" phase)
}
END {
    if (!members) fatal("empty target ownership inventory phase=finish-install")
    exit failed ? 1 : 0
}
