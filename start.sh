#!/bin/bash
set -euo pipefail

refresh_persistence() {
    local persist_dir="$1" src_dir="$2"; shift 2
    [[ -d "${src_dir}" ]] || return 0
    mkdir -p "${persist_dir}"
    while IFS= read -r -d '' src; do
        local rel="${src#"${src_dir}/"}"
        local dest="${persist_dir}/${rel}"
        mkdir -p "$(dirname "${dest}")"
        if [[ -e "${dest}" ]]; then
            rm -f "${src}"
        else
            mv "${src}" "${dest}"
        fi
    done < <(find "${src_dir}" "$@" -type f -print0 2>/dev/null)
    while IFS= read -r -d '' src; do
        [[ -e "${src}" ]] || continue
        local rel="${src#"${src_dir}/"}"
        local dest="${persist_dir}/${rel}"
        [[ -e "${dest}" ]] || mv "${src}" "${dest}"
    done < <(find "${src_dir}" "$@" -mindepth 1 -type d -print0 2>/dev/null)
    rm -rf $src_dir
    ln -sf $persist_dir $src_dir
}

# Persist credentials and config
refresh_persistence /root/persist/internal /root/.lmstudio/.internal
ln -sf /root/persist/credentials /root/.lmstudio/credentials

# Set device name
[[ -n "${LM_LINK_DEVICE_NAME:-}" ]] && /root/.lmstudio/bin/lms link set-device-name "${LM_LINK_DEVICE_NAME}"

# Start service
[[ -n "${LISTEN_PORT:-}" ]] && server_args+=(--port "${LISTEN_PORT}")
[[ -n "${BIND_ADDRESS:-}" ]] && server_args+=(--bind "${BIND_ADDRESS}")
[[ "${ENABLE_CORS:-0}" == "1" ]] && server_args+=(--cors)
/root/.lmstudio/bin/lms server start "${server_args[@]}"

# Warn if not logged in
if ! /root/.lmstudio/bin/lms whoami 2>&1 | grep -q "You are currently logged in"; then
    cat >&2 <<'EOF'

==========================================================================
⚠️ You aren't logged in to LM Studio Hub. This is expected on first run;
you can log in via `lms login`. If this isn't first run and you expected
to be logged in, make sure you're persisting /root/persist/credentials
and /root/persist/internal by mapping a host or named volume.
==========================================================================

EOF
fi

# Handoff PID to tail; retry until a log appears. `lms log stream` seems to not work.
log_file=''
for i in $(seq 1 15); do
    log_file=$(find /root/.lmstudio/server-logs -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -f2- -d' ')
    [[ -n "${log_file}" ]] && break
    sleep 1
done

[[ -z "${log_file}" ]] && { echo "No log file found after 15s" >&2; exit 1; }
exec tail -f "${log_file}"
