#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/easytier-common.sh

log() {
  printf '[entrypoint] %s\n' "$*"
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
  for pid in "${OTEL_PID:-}" "${DCGM_EXPORTER_PID:-}" "${SSHD_PID:-}" "${EASYTIER_PID:-}"; do
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

require_env ET_NETWORK_NAME
require_env ET_NETWORK_SECRET

export ET_RPC_PORTAL="$(easytier_rpc_portal)"

mkdir -p /root/.ssh /run/sshd /var/log/easytier
chmod 700 /root/.ssh

if [[ -n "${ROOT_AUTHORIZED_KEYS:-}" ]]; then
  printf '%s\n' "${ROOT_AUTHORIZED_KEYS}" > /root/.ssh/authorized_keys
fi

if [[ -f /root/.ssh/authorized_keys ]]; then
  if [[ -w /root/.ssh/authorized_keys ]]; then
    chmod 600 /root/.ssh/authorized_keys
  else
    log "authorized_keys is read-only; skipping chmod"
  fi
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
ET_ASSIGNED_CIDR="$(get_easytier_ipv4_cidr)"
export ET_ASSIGNED_IPV4
export ET_ASSIGNED_CIDR

log "easytier is ready"
log "easytier assigned ipv4: ${ET_ASSIGNED_IPV4}"
log "easytier assigned cidr: ${ET_ASSIGNED_CIDR}"

if EASYTIER_SOCKS5_PROXY="$(get_easytier_socks5_proxy)"; then
  export http_proxy="${EASYTIER_SOCKS5_PROXY}"
  export https_proxy="${EASYTIER_SOCKS5_PROXY}"
  log "easytier socks5 proxy detected: ${EASYTIER_SOCKS5_PROXY}"
fi

DCGM_EXPORTER_LISTEN="${DCGM_EXPORTER_LISTEN:-:9400}"
DCGM_EXPORTER_COLLECTORS="${DCGM_EXPORTER_COLLECTORS:-/etc/dcgm-exporter/default-counters.csv}"
DCGM_EXPORTER_WAIT_TIMEOUT="${DCGM_EXPORTER_WAIT_TIMEOUT:-30}"
DCGM_EXPORTER_POLL_INTERVAL="${DCGM_EXPORTER_POLL_INTERVAL:-1}"

if [[ ! -x /usr/local/bin/dcgm-exporter ]]; then
  log "ERROR: dcgm-exporter binary not found at /usr/local/bin/dcgm-exporter"
  exit 1
fi

if [[ ! -f "${DCGM_EXPORTER_COLLECTORS}" ]]; then
  log "ERROR: dcgm-exporter collectors file not found at ${DCGM_EXPORTER_COLLECTORS}"
  exit 1
fi

log "starting dcgm-exporter on ${DCGM_EXPORTER_LISTEN} with collectors ${DCGM_EXPORTER_COLLECTORS}"
/usr/local/bin/dcgm-exporter -a "${DCGM_EXPORTER_LISTEN}" -f "${DCGM_EXPORTER_COLLECTORS}" &
DCGM_EXPORTER_PID=$!
MANAGED_PIDS+=("${DCGM_EXPORTER_PID}")

dcgm_started_at=$SECONDS
until dcgm_exporter_is_listening; do
  if ! kill -0 "${DCGM_EXPORTER_PID}" 2>/dev/null; then
    wait "${DCGM_EXPORTER_PID}" || true
    log "ERROR: dcgm-exporter exited before it started listening"
    shutdown_children
    wait || true
    exit 1
  fi

  if (( SECONDS - dcgm_started_at >= DCGM_EXPORTER_WAIT_TIMEOUT )); then
    log "ERROR: dcgm-exporter did not start listening within ${DCGM_EXPORTER_WAIT_TIMEOUT}s"
    shutdown_children
    wait || true
    exit 1
  fi

  sleep "${DCGM_EXPORTER_POLL_INTERVAL}"
done

log "dcgm-exporter is listening on ${DCGM_EXPORTER_LISTEN}"

log "starting sshd"
/usr/sbin/sshd -D -e &
SSHD_PID=$!
MANAGED_PIDS+=("${SSHD_PID}")

if [[ -f "${OTELCOL_CONFIG_PATH}" ]]; then
  log "starting otelcol-contrib with config ${OTELCOL_CONFIG_PATH}"
  otelcol-contrib --config "${OTELCOL_CONFIG_PATH}" &
  OTEL_PID=$!
  MANAGED_PIDS+=("${OTEL_PID}")
else
  log "WARNING: OpenTelemetry Collector config not found at ${OTELCOL_CONFIG_PATH}; skipping otelcol-contrib startup"
fi

set +e
wait -n "${EASYTIER_PID}" "${MANAGED_PIDS[@]}"
exit_code=$?
set -e

log "a managed process exited, shutting down the container"
shutdown_children
wait || true
exit "${exit_code}"
