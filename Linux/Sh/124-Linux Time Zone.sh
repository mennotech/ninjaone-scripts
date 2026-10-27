# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Linux Time Zone
# ==============================================================================
#
# Description:
#   This script looks up the Time Zone database version and system Time Zone configuration. It will also apply the passed in Time Zone to the system.
#
# Metadata:
#   - NinjaOne Script ID: 124
#   - Language: sh
#   - OS Type: Linux
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2026-10-26
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-10-26 16:31:17
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#!/bin/sh
# ==============================================================================
# SYNOPSIS
#   Optionally applies an IANA time zone, then reports the current time zone
#   and TZ database version to NinjaOne.
#
# DESCRIPTION
#   When a time zone is supplied, checks that it is installed in the local
#   zoneinfo database, applies it if necessary, and verifies the result. Uses
#   timedatectl when systemd is running, otherwise updates /etc/localtime
#   directly. Keeps /etc/timezone in sync when that file exists. Does not
#   install or update tzdata or substitute a different zone when the requested
#   zone is unavailable. When no time zone is supplied, only reports.
#
#   At completion, writes the actual current time zone and the TZ database
#   version (when available) to the scriptResult device custom field, including
#   after an apply failure. Example value:
#     America/Winnipeg (TZDB 2025b, tzdata 2025b-0+deb12u1)
#   Any validation, apply, verification, or reporting failure exits with 1.
#
# PARAMETERS
#   $1  Optional IANA time zone name, for example America/Winnipeg. The
#       NinjaOne script variable timeZone (or timezone) overrides it when set
#       and not "null".
#
# NOTES
#   Run as root when applying a time zone. Written for POSIX sh (dash/bash).
#   Supports Debian/Ubuntu and Red Hat-based systems (RHEL, Rocky, Alma,
#   CentOS Stream, Fedora, Fedora CoreOS). Red Hat builds may report the TZDB
#   version with a "-rearguard" suffix, which reflects their data format.
#   The scriptResult device text field must allow Automations write access.
#
#   When the agent runs in the DTC-Inc/ninjaone-fedora-container (for example
#   on Fedora CoreOS), the script detects /usr/local/bin/in-host and re-runs
#   itself inside the host's namespaces. The host's time zone is changed and
#   reported, not the container's. The container's own time zone is unchanged.
#   Requires the container's documented setup: --privileged with host / mounted
#   at /host and host /proc at /host/proc.
#
#   Version History:
#   1.0.0 - 2026-10-26 - Apply, verify, and report the time zone and TZDB version.
#   1.1.0 - 2026-10-26 - Report UTC when /etc/localtime is absent (Fedora CoreOS)
#                        and read /etc/sysconfig/clock on older Red Hat systems.
#   1.2.0 - 2026-10-26 - Apply and report on the host when run from the
#                        ninjaone-fedora-container agent (in-host handoff).
#
# LINK
#   https://github.com/mennotech/ninjaone-scripts
#
# LICENSE
#   MIT License. See LICENSE in the repository root.
# ==============================================================================

ZONEINFO_DIR="/usr/share/zoneinfo"
NINJA_CLI="/opt/NinjaRMMAgent/programdata/ninjarmm-cli"
# Host-namespace helper provided by DTC-Inc/ninjaone-fedora-container.
IN_HOST="/usr/local/bin/in-host"
HOST_MNT_NS="/host/proc/1/ns/mnt"
# Set only when this script re-runs itself on the host from the agent container.
HostMode="${TZ_SCRIPT_HOST_MODE:-}"
ExitCode=0

is_set() {
    case "$1" in
        ""|[Nn][Uu][Ll][Ll]) return 1 ;;
        *) return 0 ;;
    esac
}

trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

get_current_zone() {
    zone=""
    if command -v timedatectl >/dev/null 2>&1; then
        zone=$(timedatectl show --property=Timezone --value 2>/dev/null)
        # Older systemd releases do not support "timedatectl show".
        if [ -z "$zone" ]; then
            zone=$(timedatectl status 2>/dev/null | sed -n 's/^[[:space:]]*Time zone: \([^ ]*\).*/\1/p')
        fi
        [ "$zone" = "n/a" ] && zone=""
    fi
    if [ -z "$zone" ] && [ -L /etc/localtime ]; then
        zone=$(readlink /etc/localtime | sed -n 's|^.*zoneinfo/||p')
    fi
    if [ -z "$zone" ] && [ -r /etc/timezone ]; then
        zone=$(trim "$(head -n 1 /etc/timezone)")
    fi
    if [ -z "$zone" ] && [ -r /etc/sysconfig/clock ]; then
        zone=$(sed -n 's/^[[:space:]]*ZONE="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' /etc/sysconfig/clock | head -n 1)
    fi
    # glibc uses UTC when /etc/localtime is absent (default on Fedora CoreOS).
    if [ -z "$zone" ] && [ ! -e /etc/localtime ]; then
        zone="UTC"
    fi
    printf '%s' "$zone"
}

get_tzdb_version() {
    version=""
    if [ -r "$ZONEINFO_DIR/tzdata.zi" ]; then
        version=$(sed -n '1s/^# version //p' "$ZONEINFO_DIR/tzdata.zi")
    fi
    if [ -z "$version" ] && [ -r "$ZONEINFO_DIR/+VERSION" ]; then
        version=$(trim "$(head -n 1 "$ZONEINFO_DIR/+VERSION")")
    fi
    printf '%s' "$version"
}

get_tzdata_package_version() {
    version=""
    if command -v dpkg-query >/dev/null 2>&1; then
        version=$(dpkg-query -W -f='${Version}' tzdata 2>/dev/null)
    fi
    if [ -z "$version" ] && command -v rpm >/dev/null 2>&1; then
        version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' tzdata 2>/dev/null) || version=""
    fi
    printf '%s' "$version"
}

# Only accept zoneinfo-style names (no "..", absolute paths, or shell
# metacharacters) that resolve to a real compiled TZif file.
test_zone_installed() {
    printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$' || return 1
    [ -f "$ZONEINFO_DIR/$1" ] || return 1
    [ "$(head -c 4 "$ZONEINFO_DIR/$1" 2>/dev/null)" = "TZif" ]
}

apply_zone() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Applying a time zone requires root. Run as root." >&2
        return 1
    fi

    # Check reporting availability before making a system change. In host mode
    # the container side has already checked and does the reporting.
    if [ -z "$HostMode" ] && [ ! -x "$NINJA_CLI" ]; then
        echo "Error: $NINJA_CLI is unavailable. Run through NinjaOne with scriptResult configured for Automations write access." >&2
        return 1
    fi

    if ! test_zone_installed "$RequestedZone"; then
        echo "Error: Time zone '$RequestedZone' is not installed on this system. Install or update the tzdata package and rerun. No replacement time zone was applied." >&2
        return 1
    fi

    CurrentZone=$(get_current_zone)
    if [ "$CurrentZone" = "$RequestedZone" ]; then
        echo "Time zone is already '$RequestedZone'. No change needed."
    else
        echo "Changing time zone from '${CurrentZone:-unknown}' to '$RequestedZone'."
        if [ -d /run/systemd/system ] && command -v timedatectl >/dev/null 2>&1; then
            if ! timedatectl set-timezone "$RequestedZone"; then
                echo "Error: timedatectl failed to set time zone '$RequestedZone'." >&2
                return 1
            fi
        else
            echo "systemd is not running; updating /etc/localtime directly."
            if ! ln -sf "$ZONEINFO_DIR/$RequestedZone" /etc/localtime; then
                echo "Error: Failed to update /etc/localtime." >&2
                return 1
            fi
        fi
    fi

    # Debian-based tools still read /etc/timezone when present.
    if [ -f /etc/timezone ] && [ "$(trim "$(head -n 1 /etc/timezone)")" != "$RequestedZone" ]; then
        echo "Updating /etc/timezone to '$RequestedZone'."
        if ! printf '%s\n' "$RequestedZone" > /etc/timezone; then
            echo "Error: Failed to update /etc/timezone." >&2
            return 1
        fi
    fi

    CurrentZone=$(get_current_zone)
    if [ "$CurrentZone" != "$RequestedZone" ]; then
        echo "Error: Time zone verification failed. Expected '$RequestedZone', but found '${CurrentZone:-unknown}'." >&2
        return 1
    fi

    echo "Verified time zone: '$CurrentZone'."
    return 0
}

report_result() {
    CurrentZone=$(get_current_zone)
    TzdbVersion=$(get_tzdb_version)
    PackageVersion=$(get_tzdata_package_version)

    if [ -z "$CurrentZone" ]; then
        echo "Error: Could not determine the current time zone." >&2
        CurrentZone="Unknown"
        ExitCode=1
    fi

    if [ -n "$TzdbVersion" ] && [ -n "$PackageVersion" ]; then
        Result="$CurrentZone (TZDB $TzdbVersion, tzdata $PackageVersion)"
    elif [ -n "$TzdbVersion" ]; then
        Result="$CurrentZone (TZDB $TzdbVersion)"
    elif [ -n "$PackageVersion" ]; then
        Result="$CurrentZone (tzdata $PackageVersion)"
    else
        Result="$CurrentZone (TZDB version unavailable)"
    fi

    echo "Current time zone: $CurrentZone"
    if [ ! -e /etc/localtime ]; then
        echo "Note: /etc/localtime is not present; the system defaults to UTC."
    fi
    echo "TZ database version: ${TzdbVersion:-unavailable}"
    echo "tzdata package version: ${PackageVersion:-unavailable}"
    echo "Local time: $(date '+%Y-%m-%d %H:%M:%S %Z (UTC%z)')"

    # ninjarmm-cli only exists in the container, so hand the result back on fd 3.
    if [ -n "$HostMode" ]; then
        printf '%s' "$Result" >&3
        return 0
    fi

    set_script_result "$Result"
}

set_script_result() {
    if [ ! -x "$NINJA_CLI" ]; then
        echo "Error: Could not report to scriptResult: $NINJA_CLI is unavailable." >&2
        return 1
    fi
    if ! "$NINJA_CLI" set scriptResult "$1"; then
        echo "Error: Could not report the current time zone to scriptResult." >&2
        return 1
    fi
    echo "Updated scriptResult to '$1'."
    return 0
}

# The agent container runs its own systemd and timedatectl, which would only
# change the container. Re-run this script inside the host's namespaces so the
# host's timedatectl, /etc/localtime, and tzdata are used, then report here.
run_on_host() {
    echo "Running in the NinjaOne agent container; applying and reporting on the host via $IN_HOST."

    if [ ! -x "$NINJA_CLI" ]; then
        echo "Error: $NINJA_CLI is unavailable. Run through NinjaOne with scriptResult configured for Automations write access." >&2
        return 1
    fi
    if [ ! -f "$0" ] || [ ! -r "$0" ]; then
        echo "Error: Cannot read this script ('$0') to run it on the host." >&2
        return 1
    fi

    exec 4>&1
    HostResult=$("$IN_HOST" env -u timeZone -u timezone TZ_SCRIPT_HOST_MODE=1 \
        sh -s -- "$RequestedZone" < "$0" 3>&1 1>&4 4>&-)
    HostExit=$?
    exec 4>&-

    if [ -z "$HostResult" ]; then
        echo "Error: The host run did not return a time zone result (exit code $HostExit)." >&2
        return 1
    fi

    set_script_result "$HostResult" || return 1
    return "$HostExit"
}

RequestedZone="${1:-}"
if is_set "${timeZone:-}"; then
    RequestedZone="$timeZone"
elif is_set "${timezone:-}"; then
    RequestedZone="$timezone"
fi
RequestedZone=$(trim "$RequestedZone")
is_set "$RequestedZone" || RequestedZone=""

if [ -z "$HostMode" ] && [ -x "$IN_HOST" ] && [ -e "$HOST_MNT_NS" ]; then
    run_on_host
    exit $?
fi

if [ -n "$RequestedZone" ]; then
    if ! apply_zone; then
        echo "Error: Could not apply time zone '$RequestedZone'." >&2
        ExitCode=1
    fi
else
    echo "No time zone specified. Reporting only."
fi

report_result || ExitCode=1

exit "$ExitCode"
