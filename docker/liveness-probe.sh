#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/easytier-common.sh

pgrep -x easytier-core >/dev/null
pgrep -x sshd >/dev/null
get_easytier_node_json >/dev/null
