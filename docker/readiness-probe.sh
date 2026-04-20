#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/easytier-common.sh

easytier_ready
sshd_is_listening
