#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/easytier-common.sh

easytier_ready
dcgm_exporter_is_listening
sshd_is_listening
