#!/bin/bash
# run.sh [-d] /path/to/workdir TYPE
#
#   TYPE of exectution:
#       shell | beakerlib
#
#   Supports __only__ one workdir to run in,
#       and only one TYPE to run the tests
#
#   Outputs results into folder specified by test name.
#       Resulting files:
#               stderr.log
#               stdout.log
#               exitcode.log
#
#   Options:
#       -d    DEBUG output
#
#

set -e
set -o pipefail

bash -n "$0"

tmt_WD=
tmt_VERBOSE=
tmt_TYPE='shell'

tmt_TESTS_D='discover'
tmt_TESTS_F="${tmt_TESTS_D}/tests.yaml"

tmt_LOG_D='execute'
tmt_LOGOUT_F="out.log"
tmt_LOGCODE_F="exitcode.log"
tmt_JOURNAL_F="journal.txt"

set -x

# TESTS_F file is on stdin
# TYPE is ARG
tmt_main () {
    local name=''
    local test=''
    local path=''
    local duration=''
    local environment=''

    local last=''

    local IFS_b="$IFS"
    IFS=''
    while read -r line; do
        local key="$(cut -d':' -f1 <<< "$line" | tmt_trim)"
        local val="$(cut -d':' -f2- <<< "$line" | tmt_trim)"

        grep -q "^\s" <<< "${line}" && {
            tmt_verbose 1 "$line"

            m=
            [[ "$key" == 'test' ]] && { m=y; test="${val}"; }
            [[ "$key" == 'path' ]] && { m=y; path="${val}"; }
            [[ "$key" == 'duration' ]] && { m=y; duration="${val}"; }
            [[ "$key" == 'environment' ]] && { m=y; environment="${val}"; }

            [[ -n "$m" ]] || tmt_error "Unknown test variable: $line"
            :
        } || {
            [[ "$name" == "$last" ]] || {
                tmt_run_test "$name" "$test" "$path" "$duration" "$environment"
                last="$name"
            }

            tmt_verbose 1 "$line"

            name="$key"
            test=''
            path=''
            duration=''
            environment=''
        }
    done

    [[ "$name" == "$last" ]] \
        || tmt_run_test "$name" "$test" "$path" "$duration" "$environment"

    local IFS="$IFS_b"
}

tmt_run_test () {
    local name="$1"
    local test="$2"
    local path="$3"
    local duration="$4"
    local environment="$5"
    local execute
    local cmd

    [[ -n "$name" ]] || {
        tmt_error "Invalid test name: '$name'" E
        return
    }
    [[ -n "$test" ]] || {
        tmt_error "[${name}] Missing test command." E
        return
    }
    [[ -z "$path" ]] || {
        path="$(readlink -f "$tmt_TESTS_D/$path")"
        [[ -d "$path" ]] || {
            tmt_error "[${name}] Could not find test dir: '$path'" E
            return
        }
        path="cd '$path' && "
    }
    [[ -z "$duration" ]] || duration="timeout '$duration' "
    [[ -z "$environment" ]] || environment="env -i $environment "

    local log_dir="${tmt_LOG_D}/$name"
    mkdir -p "$log_dir" || {
        tmt_error "[${name}] Could not create log dir: '$log_dir'" E
        return
    }
    cd "$log_dir" || {
        tmt_error "[${name}] Could not cd: '$log_dir'" E
        return
    }
    touch "$tmt_LOGOUT_F" "$tmt_LOGCODE_F" || {
        tmt_error "[${name}] Could touch log files in '$log_dir'" E
        return
    }

    cmd="${path}${environment}${duration}${test}"

    tmt_run_${tmt_TYPE} "$cmd"
    echo "$?" >"$tmt_LOGCODE_F"

    grep -q '^0$' "$tmt_LOGCODE_F" \
        && echo -n "." \
        || echo -n "F"

    [[ -z "$tmt_VERBOSE" ]] || {
        {
            tmt_verbose 2 "$tmt_LOGOUT_F:"
            cat "$tmt_LOGOUT_F"

            tmt_verbose 2 "$tmt_LOGCODE_F:"
            cat "$tmt_LOGCODE_F"

        } >&2
    }

    return 0
}

# Helpers
tmt_abort () {
    echo "Failure:" "$@" >&2
    exit 1
}

tmt_error () {
    echo "Error:" "$1" >&2

    [[ -z "$2" ]] || echo -n "$2"
}

tmt_run_shell () {
    tmt_verbose 2 "shell execute: $1"
    bash -c "$1" 1>"$tmt_LOGOUT_F" 2>&1
    return "$?"
}

tmt_run_beakerlib () {
    local result
    tmt_verbose 2 "beakerlib execute: $1"
    bash -c "export BEAKERLIB_DIR='$(pwd)'; $1" 1>"$tmt_LOGOUT_F" 2>&1

    #[[ -z "$tmt_VERBOSE" ]] || {
    #    tmt_verbose 2 "$tmt_JOURNAL_F:"
    #    cat "$tmt_JOURNAL_F" >&2
    #}

    result="$(grep '::   OVERALL RESULT: ' "$tmt_JOURNAL_F")" \
        || { tmt_error "Result not found" ; return 1 ; }

    # probably not needed
    #result="$(cut -d' ' -f3- <<< "$result")"

    grep -q 'PASS' <<< "$result" \
        && return 0

    return 1
}

tmt_trim () {
    sed -e 's/ *$//g' \
        -e 's/^ *//g'
}

tmt_verbose () {
    [[ -z "$tmt_VERBOSE" ]] || {
        local i="$1"
        local p=
        shift

        while [[ $i -gt 0 ]]; do
            p="${p} >"
            let "i=$i-1"
        done

        echo "$p" "$@" >&2
    }
}

{ set +xe; } &>/dev/null

### INIT checks
[[ 'WORKS' == "$(tmt_trim <<< "    WORKS    ")" ]] || die 'tmt_trim does not work'
[[ 'key'   == "$(cut -d':' -f1 <<< "key:value")" ]] || die 'lcut does not work'
[[ 'value' == "$(cut -d':' -f2- <<< "key:value")" ]] || die 'rcut does not work'

### ARGS processing
[[ "$1" == "-d" || "$1" == '--debug' ]] \
    && { shift; set -x; } ||:

[[ "$1" == "-v" || "$1" == '--verbose' ]] \
    && { shift; tmt_VERBOSE=y; } ||:

## Mandatory args
tmt_WD="$(readlink -f "$1")"
shift

[[ -z "$1" ]] || {
    tmt_TYPE="$1"
}
shift

[[ -z "$1" ]] || {
    tmt_STDOUT="$(readlink -f "$1")"
    touch "$tmt_STDOUT" && {
        exec >>"$tmt_STDOUT"
    } || {
        tmt_error "Could not touch or write: $tmt_STDOUT"
        tmt_error "Will not redirect STDOUT!"
    }
}
shift

[[ -z "$1" ]] || {
    tmt_STDERR="$(readlink -f "$1")"
    touch "$tmt_STDERR" && {
        exec 2>>"$tmt_STDERR"
    } || {
        tmt_error "Could not touch or write: $tmt_STDERR"
        tmt_error "Will not redirect STDERR!"
    }
}
shift

[[ -z "$1" ]] || die "Unknown arg: '$1'"


### Runtime checks
[[ -n "$tmt_WD" ]] || tmt_abort "Path to workdir is missing"
[[ -d "$tmt_WD" ]] || tmt_abort "Could not find Workdir: $tmt_WD"

[[ "$tmt_TYPE" == 'beakerlib' || "$tmt_TYPE" == 'shell' ]] \
    || tmt_abort "Unknown tests execution TYPE: '$1'"

cd "$tmt_WD" || tmt_ abort "Failed to cd: $tmt_WD"
[[ -r "$tmt_TESTS_F" ]] || tmt_abort "Could not find TESTS file: $tmt_TESTS_F"
[[ `wc -l "$tmt_TESTS_F" | cut -d' ' -f1` -gt 1 ]] || tmt_abort "Missing tests. (`cat "$tmt_TESTS_F"`)"

tmt_TESTS_D="$(readlink -f "${tmt_WD}/${tmt_TESTS_D}")"
[[ -d "$tmt_TESTS_D" ]] || tmt_abort "Could not find Discover dir: $tmt_TESTS_D"

tmt_LOG_D="$(readlink -f "${tmt_WD}/${tmt_LOG_D}")"
[[ -d "$tmt_LOG_D" ]] || tmt_abort "Could not find Execute dir: $tmt_LOG_D"


### RUN
tmt_verbose 0 "$tmt_WD $ main $tmt_TYPE < $tmt_TESTS_F"

tmt_main < <( grep -vE '^\s*$' "$tmt_TESTS_F" )

echo 'D'
