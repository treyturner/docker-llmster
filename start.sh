#!/bin/bash
set -euo pipefail

# Warn if not logged in
if ! /root/.lmstudio/bin/lms whoami 2>&1 | grep -q "You are currently logged in"; then
    echo >&2
    echo ".+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+." >&2
    echo "⚠️ You aren't logged in to LM Studio Hub. This is expected on" >&2
    echo "first run; you can log in via \`lms login\`. If this isn't first" >&2
    echo "run and you expected to be logged in, make sure you're persisting" >&2
    echo "/root/.lmstudio/credentials by mapping a host or named volume." >&2
    echo ".+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+.+"+." >&2
    echo >&2
fi

# Set device name
if [[ -n "${LM_LINK_DEVICE_NAME:-}" ]]; then
    /root/.lmstudio/bin/lms link set-device-name "${LM_LINK_DEVICE_NAME}"
fi

# Start service
server_args=()
[[ -n "${LISTEN_PORT:-}" ]] && server_args+=(--port "${LISTEN_PORT}")
[[ -n "${BIND_ADDRESS:-}" ]] && server_args+=(--bind "${BIND_ADDRESS}")
[[ "${ENABLE_CORS:-0}" == "1" ]] && server_args+=(--cors)
/root/.lmstudio/bin/lms server start "${server_args[@]}"

# Hand process to log tail — retry until a log file appears
log_file=''
for i in $(seq 1 30); do
    log_file=$(find /root/.lmstudio/server-logs -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -f2- -d' ')
    [[ -n "${log_file}" ]] && break
    sleep 1
done
[[ -z "${log_file}" ]] && { echo "No log file found after 30s" >&2; exit 1; }
exec tail -f "${log_file}"
