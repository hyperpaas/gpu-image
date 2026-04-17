#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[entrypoint] %s\n' "$*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log "ERROR: required environment variable ${name} is not set"
    exit 1
  fi
}

shutdown_children() {
  local pid
  for pid in "${OTEL_PID:-}" "${SSHD_PID:-}" "${EASYTIER_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

on_signal() {
  log "received termination signal, stopping services"
  shutdown_children
  wait || true
  exit 143
}

trap on_signal INT TERM HUP QUIT

OTELCOL_CONFIG_PATH='/etc/otelcol/config.yaml'
MANAGED_PIDS=()

easytier_ready() {
  local peer_output expected_peers peer_count required_peers local_ipv4

  local_ipv4="$(get_easytier_ipv4)"
  [[ -n "${local_ipv4}" ]] || return 1

  required_peers=0
  if [[ -n "$(trim "${ET_PEERS:-}")" ]]; then
    required_peers=1
  fi

  expected_peers="$(trim "${ET_EXPECT_PEERS:-${required_peers}}")"
  if [[ "${expected_peers}" =~ ^[0-9]+$ ]] && (( expected_peers > 0 )); then
    peer_output="$(easytier-cli --rpc-portal "${ET_RPC_PORTAL}" peer 2>/dev/null || true)"
    peer_count="$(grep -Eoc '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${peer_output}" || true)"
    (( peer_count >= expected_peers )) || return 1
  fi

  return 0
}

get_easytier_ipv4() {
  local node_output ipv4

  node_output="$(easytier-cli --rpc-portal "${ET_RPC_PORTAL}" --output json node 2>/dev/null || true)"
  [[ -n "${node_output}" ]] || return 1

  ipv4="$(jq -r '.ipv4_addr // empty' <<< "${node_output}" 2>/dev/null || true)"
  ipv4="$(trim "${ipv4}")"

  [[ -n "${ipv4}" ]] || return 1
  [[ "${ipv4}" == "null" ]] && return 1
  [[ "${ipv4}" == "0.0.0.0" ]] && return 1
  [[ "${ipv4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  printf '%s\n' "${ipv4}"
}

require_env ET_NETWORK_NAME
require_env ET_NETWORK_SECRET

export ET_RPC_PORTAL="${ET_RPC_PORTAL:-127.0.0.1:15888}"

mkdir -p /root/.ssh /run/sshd /var/log/easytier
chmod 700 /root/.ssh

if [[ -n "${ROOT_AUTHORIZED_KEYS:-}" ]]; then
  printf '%s\n' "${ROOT_AUTHORIZED_KEYS}" > /root/.ssh/authorized_keys
fi

if [[ -f /root/.ssh/authorized_keys ]]; then
  chmod 600 /root/.ssh/authorized_keys
else
  log "WARNING: /root/.ssh/authorized_keys not found; sshd will start but no root key is configured"
fi

ssh-keygen -A >/dev/null

log "starting easytier-core"
easytier-core &
EASYTIER_PID=$!

wait_timeout="${ET_WAIT_TIMEOUT:-120}"
poll_interval="${ET_POLL_INTERVAL:-2}"
started_at=$SECONDS

until easytier_ready; do
  if ! kill -0 "${EASYTIER_PID}" 2>/dev/null; then
    wait "${EASYTIER_PID}" || true
    log "ERROR: easytier-core exited before the network became ready"
    exit 1
  fi

  if (( SECONDS - started_at >= wait_timeout )); then
    log "ERROR: easytier did not become ready within ${wait_timeout}s"
    shutdown_children
    wait || true
    exit 1
  fi

  sleep "${poll_interval}"
done

ET_ASSIGNED_IPV4="$(get_easytier_ipv4)"
export ET_ASSIGNED_IPV4

log "easytier is ready"
log "easytier assigned ipv4: ${ET_ASSIGNED_IPV4}"

log "starting sshd"
/usr/sbin/sshd -D -e &
SSHD_PID=$!
MANAGED_PIDS+=("${SSHD_PID}")

if [[ -f "${OTELCOL_CONFIG_PATH}" ]]; then
  log "starting otelcol with config ${OTELCOL_CONFIG_PATH}"
  otelcol --config "${OTELCOL_CONFIG_PATH}" &
  OTEL_PID=$!
  MANAGED_PIDS+=("${OTEL_PID}")
else
  log "WARNING: OpenTelemetry Collector config not found at ${OTELCOL_CONFIG_PATH}; skipping otelcol startup"
fi

set +e
wait -n "${EASYTIER_PID}" "${MANAGED_PIDS[@]}"
exit_code=$?
set -e

log "a managed process exited, shutting down the container"
shutdown_children
wait || true
exit "${exit_code}"
