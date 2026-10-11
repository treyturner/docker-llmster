#!/bin/bash
set -euo pipefail

persist_child_path() {
    local persist_dir="$1" src_dir="$2" rel="$3" kind="$4"
    local src="${src_dir}/${rel}" dest="${persist_dir}/${rel}"

    mkdir -p "$(dirname "${src}")" "$(dirname "${dest}")"
    [[ -L "${src}" ]] && rm -f "${src}"

    if [[ -e "${src}" && ! -e "${dest}" ]]; then
        mv "${src}" "${dest}"
    elif [[ -f "${src}" && -f "${dest}" ]]; then
        if [[ "${src}" -nt "${dest}" ]]; then
            mv -f "${src}" "${dest}"
        else
            rm -f "${src}"
        fi
    elif [[ -d "${src}" && -d "${dest}" ]]; then
        shopt -s dotglob nullglob
        local child child_dest
        for child in "${src}"/*; do
            child_dest="${dest}/$(basename "${child}")"
            [[ -e "${child_dest}" ]] || mv "${child}" "${child_dest}"
        done
        rm -rf "${src}"
    else
        rm -rf "${src}"
    fi

    [[ "${kind}" == "dir" ]] && mkdir -p "${dest}"
    ln -s "${dest}" "${src}"
}

should_persist_internal_path() {
    local rel="$1"

    case "${rel}" in
        ''|'.'|'..'|app-install-location.json|daemon-update.json|http-server-ctl.json|llmster-install-location.json|llmster-pid.lock|temp|utils)
            return 1
            ;;
    esac

    return 0
}

link_existing_persisted_internal() {
    local persist_dir="$1" src_dir="$2"
    local dest rel kind

    while IFS= read -r -d '' dest; do
        rel="$(basename "${dest}")"
        should_persist_internal_path "${rel}" || continue

        kind=file
        [[ -d "${dest}" ]] && kind=dir
        persist_child_path "${persist_dir}" "${src_dir}" "${rel}" "${kind}"
    done < <(find "${persist_dir}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
}

link_existing_local_internal() {
    local persist_dir="$1" src_dir="$2"
    local src rel kind

    while IFS= read -r -d '' src; do
        [[ -L "${src}" ]] && continue

        rel="$(basename "${src}")"
        should_persist_internal_path "${rel}" || continue

        kind=file
        [[ -d "${src}" ]] && kind=dir
        persist_child_path "${persist_dir}" "${src_dir}" "${rel}" "${kind}"
    done < <(find "${src_dir}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
}

sync_internal_to_persist() {
    local persist_dir="/root/persist/internal"
    local src_dir="/root/.lmstudio/.internal"
    local src rel dest

    [[ -d "${src_dir}" ]] || return 0
    mkdir -p "${persist_dir}"

    while IFS= read -r -d '' src; do
        [[ -L "${src}" ]] && continue

        rel="$(basename "${src}")"
        should_persist_internal_path "${rel}" || continue

        dest="${persist_dir}/${rel}"
        if [[ -d "${src}" ]]; then
            mkdir -p "${dest}"
            cp -au "${src}/." "${dest}/"
        elif [[ -f "${src}" && ( ! -e "${dest}" || "${src}" -nt "${dest}" ) ]]; then
            cp -a "${src}" "${dest}"
        fi
    done < <(find "${src_dir}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
}

sync_internal_to_persist_loop() {
    # llmster can atomically rewrite files, which replaces file symlinks.
    # Mirror those real files back into the mounted persistence directory.
    while true; do
        sync_internal_to_persist || true
        sleep 2
    done
}

persist_internal() {
    local persist_dir="/root/persist/internal"
    local src_dir="/root/.lmstudio/.internal"
    local rel
    local dirs=(
        api-prediction-history
        bundled-models
        cached-rag-pipeline-chunks
        config-presets-drafts
        files
        global-hotkeys
        parsed-documents-cache
        retrieval-sessions
        staged-updates-app
        temp-downloads
        ui-state
        user-concrete-model-default-config
    )
    local files=(
        2Fkeys.json
        artifact-permissions-list.json
        asr-model-selection.json
        backend-preferences-v1.json
        bookmarks.json
        dev-logs-state.json
        document-parsing-cache-v1.json
        download-jobs-info.json
        draft-model-compatibility-cache.json
        gguf-metadata-cache.json
        global-plugin-configs.json
        hardware-config.json
        historical-version-info.json
        http-server-config.json
        internal-engine-index.json
        last-synced-mcp-state.json
        lm-link-account-status-cache.json
        lm-link-config.json
        lms-key-2
        local-identity.json
        mcp-bridge-config.json
        mcp.json
        model-index-cache.json
        permissions-store.json
        persistent-extension-pack-state.json
        projects-registry.json
        recent-projects.json
        runtime-selections.json
        server-logs-state.json
        settings.json
        single-downloads-info.json
    )

    mkdir -p "${persist_dir}" "${src_dir}"
    link_existing_persisted_internal "${persist_dir}" "${src_dir}"
    link_existing_local_internal "${persist_dir}" "${src_dir}"
    for rel in "${dirs[@]}"; do
        persist_child_path "${persist_dir}" "${src_dir}" "${rel}" dir
    done
    for rel in "${files[@]}"; do
        persist_child_path "${persist_dir}" "${src_dir}" "${rel}" file
    done
}

persist_credentials() {
    local persist_dir="/root/persist/credentials"
    local src_dir="/root/.lmstudio/credentials"

    mkdir -p "${persist_dir}"
    [[ -L "${src_dir}" ]] && rm -f "${src_dir}"
    if [[ -d "${src_dir}" ]]; then
        shopt -s dotglob nullglob
        local child child_dest
        for child in "${src_dir}"/*; do
            child_dest="${persist_dir}/$(basename "${child}")"
            [[ -e "${child_dest}" ]] || mv "${child}" "${child_dest}"
        done
        rm -rf "${src_dir}"
    fi
    ln -s "${persist_dir}" "${src_dir}"
}

write_permissions_store() {
    local store="$1" content="$2"
    local tmp="${store}.tmp.$$"

    (umask 077 && printf '%s\n' "${content}" > "${tmp}")
    mv -f "${tmp}" "${store}"
}

configure_api_token() {
    # llmster reads its API token store (SuperJSON-wrapped) once at startup.
    # Only the token entry labeled below is managed; tokens created elsewhere are kept.
    local store="/root/persist/internal/permissions-store.json"
    local label="LM_API_TOKEN (docker-llmster)"
    local token="${LM_API_TOKEN:-}"
    local current updated

    if [[ -z "${token}" && -n "${LM_API_TOKEN_FILE:-}" ]]; then
        [[ -r "${LM_API_TOKEN_FILE}" ]] || { echo "LM_API_TOKEN_FILE is not readable: ${LM_API_TOKEN_FILE}" >&2; exit 1; }
        token="$(tr -d '[:space:]' < "${LM_API_TOKEN_FILE}")"
    fi

    current='{"json":{"tokenMode":"disabled","tokens":[],"serverPermissions":{}}}'
    if [[ -s "${store}" ]]; then
        if ! jq -e '.json | type == "object"' "${store}" >/dev/null 2>&1; then
            echo "Refusing to modify unrecognized API token store: ${store}" >&2
            [[ -n "${token}" ]] && exit 1
            return 0
        fi
        current="$(cat "${store}")"
    elif [[ -z "${token}" ]]; then
        return 0
    fi

    if [[ -z "${token}" ]]; then
        # Drop a previously env-managed token; disable auth if no tokens remain.
        jq -e --arg managed "${label}" '(.json.tokens // []) | any(.label == $managed)' <<<"${current}" >/dev/null || return 0
        updated="$(jq --arg managed "${label}" '
            .json.tokens = ((.json.tokens // []) | map(select(.label != $managed)))
            | if (.json.tokens | length) == 0 then .json.tokenMode = "disabled" else . end
        ' <<<"${current}")"
        write_permissions_store "${store}" "${updated}"
        echo "LM_API_TOKEN unset; removed its token from the API token store." >&2
        return 0
    fi

    if [[ ! "${token}" =~ ^sk-lm-([A-Za-z0-9]{8}):([A-Za-z0-9]{20})$ ]]; then
        echo "LM_API_TOKEN must match sk-lm-<8 letters/digits>:<20 letters/digits>" >&2
        exit 1
    fi
    local id="${BASH_REMATCH[1]}"
    local hash
    hash="$(printf '%s' "${BASH_REMATCH[2]}" | openssl dgst -sha512 -binary | base64 -w0)"

    updated="$(jq --arg managed "${label}" --arg id "${id}" --arg hash "${hash}" \
        --argjson now "$(($(date +%s) * 1000))" '
        ((.json.tokens // []) | map(select(.label == $managed and .clientIdentifier == $id
            and .clientPasskeySHA512Base64 == $hash)) | first) as $prev
        | .json.tokenMode = "required"
        | .json.serverPermissions = (.json.serverPermissions // {})
        | .json.tokens = ((.json.tokens // [])
            | map(select(.label != $managed and .clientIdentifier != $id)))
            + [{
                clientIdentifier: $id,
                clientPasskeySHA512Base64: $hash,
                label: $managed,
                createdAt: ($prev.createdAt // $now),
                lastUsedAt: ($prev.lastUsedAt // null),
                permissions: ($prev.permissions // {})
            }]
    ' <<<"${current}")"

    if [[ "$(jq -cS . <<<"${updated}")" != "$(jq -cS . <<<"${current}")" ]]; then
        write_permissions_store "${store}" "${updated}"
    fi
}

warn_if_exposed_without_auth() {
    local store="/root/persist/internal/permissions-store.json"
    local config="/root/persist/internal/http-server-config.json"
    local bind="${BIND_ADDRESS:-}"

    [[ -z "${bind}" && -s "${config}" ]] && bind="$(jq -r '.networkInterface // empty' "${config}" 2>/dev/null || true)"
    case "${bind}" in ''|127.*|localhost|::1) return 0 ;; esac
    [[ -s "${store}" ]] && jq -e '.json.tokenMode == "required"' "${store}" >/dev/null 2>&1 && return 0

    cat >&2 <<EOF

==========================================================================
🚨 The server is bound to ${bind} with NO API token authentication.
Anything that can reach this port can use it. Set LM_API_TOKEN to
require a token; see the Security section of the README.
==========================================================================

EOF
}

# Persist credentials and config
persist_internal
persist_credentials
configure_api_token
sync_internal_to_persist_loop &

lms_bin="/root/.lmstudio/llmster/$(cat /root/version)/.bundle/lms"
server_args=()

# Start daemon
"${lms_bin}" daemon up >/dev/null

# Set device name
[[ -n "${LM_LINK_DEVICE_NAME:-}" ]] && "${lms_bin}" link set-device-name "${LM_LINK_DEVICE_NAME}"

# Start service
[[ -n "${LISTEN_PORT:-}" ]] && server_args+=(--port "${LISTEN_PORT}")
[[ -n "${BIND_ADDRESS:-}" ]] && server_args+=(--bind "${BIND_ADDRESS}")
[[ "${ENABLE_CORS:-0}" == "1" ]] && server_args+=(--cors)
"${lms_bin}" server start "${server_args[@]}"
warn_if_exposed_without_auth

# Warn if not logged in
if ! "${lms_bin}" whoami 2>&1 | grep -q "You are currently logged in"; then
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
