# Restricted credential and compiled-snapshot data grammar. No shell evaluation or ENVIRON.
# Snapshot callers use the serialized assignment grammar; credential callers
# supply only the requested mapped name and may carry any PRESEED_* field for
# another consumer.
BEGIN {
    snapshot = mode == "snapshot"
    credentials = mode == "credential"
    if (mode != "" && !snapshot && !credentials) { failed = 1; exit 2 }
    if (credentials && wanted !~ /^PRESEED_[A-Za-z0-9_]*$/) {
        failed = 1
        exit 2
    }
}
function fail() { failed = 1; exit 2 }
function literal(raw,    quote, value, i, c, nextc, result) {
    quote = substr(raw, 1, 1)
    if (quote == "\047" || quote == "\042") {
        if (length(raw) < 2 || substr(raw, length(raw)) != quote) fail()
        value = substr(raw, 2, length(raw)-2)
        result = ""
        for (i = 1; i <= length(value); i++) {
            c = substr(value, i, 1)
            # Private snapshots and credential inputs use the serializer's
            # exact POSIX single-quote escape. Decode those four bytes as
            # literal data; never evaluate the value or permit shell syntax.
            if ((snapshot || credentials) && quote == "\047" && substr(value, i, 4) == "\047\\\047\047") {
                result = result quote
                i += 3
                continue
            }
            if (c == quote) fail()
            if (c == "\\" && quote == "\042") {
                if (++i > length(value)) fail()
                nextc = substr(value, i, 1)
                if (index("\\\042$`", nextc) == 0) fail()
                c = nextc
            }
            result = result c
        }
        return result
    }
    # Credential files are data, not shell programs. Accept printable
    # unquoted values so an unattended input does not depend on a particular
    # quoting convention. Snapshot values remain serializer-bound.
    if (credentials) return raw
    if (raw ~ /[^A-Za-z0-9_.,:@%+\/-]/) fail()
    return raw
}
{
    bytes += length($0) + 1
    if (bytes > (snapshot ? 1048576 : 65536) || NR > (snapshot ? 4096 : 512) || $0 ~ /[[:cntrl:]]/) fail()
    credential_line = $0
    if (credentials) {
        # A private env file may be assembled from a shell-exporting source.
        # Remove only the data-file spelling; never evaluate the line.
        sub(/^[ ]+/, "", credential_line)
        sub(/^export[ ]+/, "", credential_line)
    }
    if (credential_line == "" || credential_line ~ /^#/) next
    separator = index(credential_line, "=")
    if (separator < 2) fail()
    key = substr(credential_line, 1, separator-1)
    if (snapshot) {
        if (key !~ /^[A-Z][A-Z0-9_]*$/ || key ~ /^(HOME|PATH|IFS|ENV|BASH_ENV|SHELLOPTS|BASHOPTS|ZDOTDIR|PYTHONPATH|PERL5LIB|LD_.*)$/) fail()
        if (substr(credential_line, separator+1, 1) != "\047") fail()
    } else if (key !~ /^PRESEED_[A-Za-z0-9_]*$/) fail()
    if (key in seen) fail()
    order[++entries] = key
    seen[key] = 1
    data[key] = literal(substr(credential_line, separator+1))
}
END {
    if (failed) exit 2
    if (snapshot) {
        for (i = 1; i <= entries; i++) {
            print order[i]
            print data[order[i]]
        }
        # Retain empty final values across shell command substitution.
        print "__INSTALLER_DATA_END__"
    } else {
        if (!(wanted in seen)) exit 1
        print data[wanted]
    }
}
