#!/usr/bin/env bash

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

easytier_rpc_portal() {
  printf '%s\n' "${ET_RPC_PORTAL:-127.0.0.1:15888}"
}

get_easytier_node_json() {
  easytier-cli --rpc-portal "$(easytier_rpc_portal)" --output json node 2>/dev/null || true
}

get_easytier_peer_json() {
  easytier-cli --rpc-portal "$(easytier_rpc_portal)" --output json peer 2>/dev/null || true
}

get_easytier_ipv4() {
  local node_output ipv4

  node_output="$(get_easytier_node_json)"
  [[ -n "${node_output}" ]] || return 1

  ipv4="$(jq -r '.ipv4_addr // empty | split("/")[0]' <<< "${node_output}" 2>/dev/null || true)"
  ipv4="$(trim "${ipv4}")"

  [[ -n "${ipv4}" ]] || return 1
  [[ "${ipv4}" == "null" ]] && return 1
  [[ "${ipv4}" == "0.0.0.0" ]] && return 1
  [[ "${ipv4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  printf '%s\n' "${ipv4}"
}

get_easytier_ipv4_cidr() {
  local node_output ipv4_cidr

  node_output="$(get_easytier_node_json)"
  [[ -n "${node_output}" ]] || return 1

  ipv4_cidr="$(jq -r '.ipv4_addr // empty' <<< "${node_output}" 2>/dev/null || true)"
  ipv4_cidr="$(trim "${ipv4_cidr}")"

  [[ -n "${ipv4_cidr}" ]] || return 1
  [[ "${ipv4_cidr}" == "null" ]] && return 1
  [[ "${ipv4_cidr}" == "0.0.0.0" ]] && return 1
  [[ "${ipv4_cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || return 1

  printf '%s\n' "${ipv4_cidr}"
}

get_easytier_socks5_proxy() {
  local node_output config_text proxy_url proxy_host

  node_output="$(get_easytier_node_json)"
  [[ -n "${node_output}" ]] || return 1

  config_text="$(jq -r '.config // empty' <<< "${node_output}" 2>/dev/null || true)"
  [[ -n "${config_text}" ]] || return 1

  proxy_url="$(sed -nE 's/.*socks5_proxy[[:space:]]*=[[:space:]]*"(socks5:\/\/[^\"]+)".*/\1/p' <<< "${config_text}" | head -n 1)"
  proxy_url="$(trim "${proxy_url}")"
  [[ -n "${proxy_url}" ]] || return 1

  proxy_host="$(sed -nE 's#^socks5://\[?([^]/:]+|::)\]?:[0-9]+$#\1#p' <<< "${proxy_url}" | head -n 1)"
  case "${proxy_host}" in
    0.0.0.0|::|'')
      proxy_url="$(sed -E 's#^socks5://\[?(0\.0\.0\.0|::)\]?:#socks5://127.0.0.1:#' <<< "${proxy_url}")"
      ;;
  esac

  printf '%s\n' "${proxy_url}"
}

get_expected_peer_count() {
  local required_peers expected_peers

  required_peers=0
  if [[ -n "$(trim "${ET_PEERS:-}")" ]]; then
    required_peers=1
  fi

  expected_peers="$(trim "${ET_EXPECT_PEERS:-${required_peers}}")"
  if [[ "${expected_peers}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${expected_peers}"
  else
    printf '0\n'
  fi
}

get_connected_peer_count() {
  local peer_output peer_count

  peer_output="$(get_easytier_peer_json)"
  [[ -n "${peer_output}" ]] || return 1

  peer_count="$(jq -r 'if type == "array" then [.[] | select((.cost // "") != "Local")] | length else 0 end' <<< "${peer_output}" 2>/dev/null || true)"
  [[ "${peer_count}" =~ ^[0-9]+$ ]] || return 1

  printf '%s\n' "${peer_count}"
}

easytier_ready() {
  local local_ipv4 expected_peers peer_count

  local_ipv4="$(get_easytier_ipv4)"
  [[ -n "${local_ipv4}" ]] || return 1

  expected_peers="$(get_expected_peer_count)"
  if (( expected_peers > 0 )); then
    peer_count="$(get_connected_peer_count)"
    [[ "${peer_count}" =~ ^[0-9]+$ ]] || return 1
    (( peer_count >= expected_peers )) || return 1
  fi

  return 0
}

sshd_is_listening() {
  local state recv_q send_q local_address peer_address

  while read -r state recv_q send_q local_address peer_address; do
    case "${local_address}" in
      *:22|*\]:22)
        return 0
        ;;
    esac
  done < <(ss -ltnH 2>/dev/null || true)

  return 1
}
