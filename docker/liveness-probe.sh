#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/easytier-common.sh

pgrep -x easytier-core >/dev/null
pgrep -x dcgm-exporter >/dev/null
pgrep -x sshd >/dev/null
dcgm_exporter_is_listening
get_easytier_node_json >/dev/null
