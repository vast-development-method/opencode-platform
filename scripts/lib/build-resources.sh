#!/usr/bin/env bash
set -Eeuo pipefail

read_meminfo_mib() {
    local key="${1:?meminfo key required}"
    local override_name
    case "$key" in
        MemTotal) override_name=VDM_TEST_MEM_TOTAL_MIB ;;
        MemAvailable) override_name=VDM_TEST_MEM_AVAILABLE_MIB ;;
        *) override_name="VDM_TEST_${key^^}_MIB" ;;
    esac
    local override="${!override_name:-}"

    if [ -n "$override" ]; then
        [[ "$override" =~ ^[0-9]+$ ]] || die "$override_name must be an integer MiB value"
        printf '%s\n' "$override"
        return
    fi

    awk -v key="$key" '
        $1 == key ":" {
            printf "%d\n", $2 / 1024
            found = 1
            exit
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' /proc/meminfo || die "Unable to read $key from /proc/meminfo"
}

online_cpu_count() {
    if [ -n "${VDM_TEST_CPU_COUNT:-}" ]; then
        [[ "$VDM_TEST_CPU_COUNT" =~ ^[1-9][0-9]*$ ]] ||
            die "VDM_TEST_CPU_COUNT must be a positive integer"
        printf '%s\n' "$VDM_TEST_CPU_COUNT"
        return
    fi

    getconf _NPROCESSORS_ONLN
}

storage_available_gib() {
    local pool="${1:?storage pool required}"
    local info
    local used
    local total
    local path
    local available_kib

    if [ -n "${VDM_TEST_DISK_AVAILABLE_GIB:-}" ]; then
        [[ "$VDM_TEST_DISK_AVAILABLE_GIB" =~ ^[0-9]+$ ]] ||
            die "VDM_TEST_DISK_AVAILABLE_GIB must be an integer GiB value"
        printf '%s\n' "$VDM_TEST_DISK_AVAILABLE_GIB"
        return
    fi

    info="$(incus_cmd storage info "$pool" --bytes 2>/dev/null || true)"
    used="$(
        awk -F': *' 'tolower($1) == "space used" {print $2; exit}' <<< "$info"
    )"
    total="$(
        awk -F': *' 'tolower($1) == "space total" {print $2; exit}' <<< "$info"
    )"
    if [[ "$used" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ && "$total" -ge "$used" ]]; then
        printf '%s\n' "$(((total - used) / 1024 / 1024 / 1024))"
        return
    fi

    path="${VDM_BUILD_STORAGE_PATH:-}"
    if [ -z "$path" ]; then
        if [ -e /var/lib/incus ]; then
            path=/var/lib/incus
        else
            path="$ROOT_DIR"
        fi
    fi
    available_kib="$(df --output=avail -k "$path" | awk 'NR == 2 {print $1}')"
    [[ "$available_kib" =~ ^[0-9]+$ ]] ||
        die "Unable to determine free space for Incus storage pool $pool"
    printf '%s\n' "$((available_kib / 1024 / 1024))"
}

select_build_resources() {
    local variant="${1:?variant required}"
    local storage_pool="${2:?storage pool required}"
    local cache_enabled="${3:-true}"
    local total_mib
    local available_mib
    local reserve_mib
    local percent_reserve_mib
    local safe_memory_mib
    local min_cpus
    local min_memory_gib
    local min_memory_mib
    local preferred_memory_gib
    local preferred_memory_mib
    local disk_gib
    local cpus
    local safe_cpus
    local available_disk_gib
    local required_disk_gib

    variant_exists "$variant" || die "Unknown build variant: $variant"

    total_mib="$(read_meminfo_mib MemTotal)"
    available_mib="$(read_meminfo_mib MemAvailable)"
    cpus="$(online_cpu_count)"
    min_cpus="${PLATFORM_BUILD_MIN_CPUS[$variant]}"
    min_memory_gib="${PLATFORM_BUILD_MIN_MEMORY_GIB[$variant]}"
    preferred_memory_gib="${PLATFORM_BUILD_PREFERRED_MEMORY_GIB[$variant]}"
    disk_gib="${PLATFORM_BUILD_DISK_GIB[$variant]}"

    percent_reserve_mib="$(((
        total_mib * PLATFORM_BUILD_HOST_MEMORY_RESERVE_PERCENT + 99
    ) / 100))"
    reserve_mib="$((PLATFORM_BUILD_HOST_MEMORY_RESERVE_MIN_GIB * 1024))"
    if ((percent_reserve_mib > reserve_mib)); then
        reserve_mib="$percent_reserve_mib"
    fi

    safe_memory_mib="$((
        available_mib - reserve_mib - PLATFORM_BUILD_QEMU_OVERHEAD_MIB
    ))"
    min_memory_mib="$((min_memory_gib * 1024))"
    preferred_memory_mib="$((preferred_memory_gib * 1024))"

    if ((safe_memory_mib < min_memory_mib)); then
        die "Insufficient currently available memory for $variant: ${available_mib} MiB available; $((min_memory_mib + reserve_mib + PLATFORM_BUILD_QEMU_OVERHEAD_MIB)) MiB required (${min_memory_mib} MiB guest + ${reserve_mib} MiB host reserve + ${PLATFORM_BUILD_QEMU_OVERHEAD_MIB} MiB QEMU overhead). Close other workloads and retry. Swap is not required and is not counted."
    fi

    BUILD_SELECTED_MEMORY_MIB="$preferred_memory_mib"
    if ((safe_memory_mib < BUILD_SELECTED_MEMORY_MIB)); then
        BUILD_SELECTED_MEMORY_MIB="$safe_memory_mib"
    fi
    # Incus accepts MiB and integer values avoid unsafe floating-point shell math.
    BUILD_SELECTED_MEMORY="${BUILD_SELECTED_MEMORY_MIB}MiB"

    safe_cpus="$((cpus - PLATFORM_BUILD_HOST_CPU_RESERVE))"
    if ((safe_cpus < min_cpus)); then
        die "Insufficient online CPUs for $variant: $cpus available; $min_cpus guest CPUs plus $PLATFORM_BUILD_HOST_CPU_RESERVE host CPU required."
    fi
    BUILD_SELECTED_CPUS="${PLATFORM_BUILD_PREFERRED_CPUS[$variant]}"
    if ((safe_cpus < BUILD_SELECTED_CPUS)); then
        BUILD_SELECTED_CPUS="$safe_cpus"
    fi

    required_disk_gib="$((disk_gib + PLATFORM_BUILD_HOST_DISK_RESERVE_GIB))"
    if [ "$cache_enabled" = true ]; then
        required_disk_gib="$((
            required_disk_gib + PLATFORM_BUILD_CACHE_SIZE_GIB
        ))"
    fi
    if ((MIN_BUILD_FREE_GIB > required_disk_gib)); then
        required_disk_gib="$MIN_BUILD_FREE_GIB"
    fi
    available_disk_gib="$(storage_available_gib "$storage_pool")"
    if ((available_disk_gib < required_disk_gib)); then
        die "Insufficient Incus storage for $variant: ${available_disk_gib} GiB available; ${required_disk_gib} GiB required."
    fi

    BUILD_SELECTED_DISK="${disk_gib}GiB"
    BUILD_REQUIRED_FREE_GIB="$required_disk_gib"
    BUILD_HOST_TOTAL_MIB="$total_mib"
    BUILD_HOST_AVAILABLE_MIB="$available_mib"
    BUILD_HOST_RESERVE_MIB="$reserve_mib"
    BUILD_HOST_CPUS="$cpus"
    BUILD_STORAGE_AVAILABLE_GIB="$available_disk_gib"

    export \
        BUILD_SELECTED_MEMORY_MIB \
        BUILD_SELECTED_MEMORY \
        BUILD_SELECTED_CPUS \
        BUILD_SELECTED_DISK \
        BUILD_REQUIRED_FREE_GIB \
        BUILD_HOST_TOTAL_MIB \
        BUILD_HOST_AVAILABLE_MIB \
        BUILD_HOST_RESERVE_MIB \
        BUILD_HOST_CPUS \
        BUILD_STORAGE_AVAILABLE_GIB
}

print_build_resource_plan() {
    local variant="${1:?variant required}"

    log "Safe build plan for $variant"
    printf 'Host: %s CPUs, %s MiB total, %s MiB currently available\n' \
        "$BUILD_HOST_CPUS" "$BUILD_HOST_TOTAL_MIB" "$BUILD_HOST_AVAILABLE_MIB"
    printf 'Reserved for host: %s MiB memory and %s CPU\n' \
        "$BUILD_HOST_RESERVE_MIB" "$PLATFORM_BUILD_HOST_CPU_RESERVE"
    printf 'Build VM: %s CPUs, %s memory, %s disk\n' \
        "$BUILD_SELECTED_CPUS" "$BUILD_SELECTED_MEMORY" "$BUILD_SELECTED_DISK"
    printf 'Incus storage: %s GiB available, %s GiB safety requirement\n' \
        "$BUILD_STORAGE_AVAILABLE_GIB" "$BUILD_REQUIRED_FREE_GIB"
}
