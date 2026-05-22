ARG DCGM_EXPORTER_VERSION=4.5.3-4.8.2
ARG DCGM_EXPORTER_IMAGE=nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2-distroless@sha256:60d3b00ac80b4ae77f94dae2f943685605585ad9e92fdccda3154d009ae317cc

FROM ${DCGM_EXPORTER_IMAGE} AS dcgm-exporter

FROM debian:trixie-slim

ARG TARGETARCH
ARG EASYTIER_VERSION=v2.4.5
ARG EASYTIER_SHA256_AMD64=d33d1fe6e06fae6155ca7a6ea214657de8d29c4edd5e16fb51f128bef29d3aec
ARG OTELCOL_VERSION=0.150.1
ARG OTELCOL_CONTRIB_SHA256_AMD64=c8ded6c8dbe38e63b63fbfb86b5eff485ba91616254b58ae21dc71d03ba1b922
ARG DCGM_EXPORTER_VERSION

ENV ET_RPC_PORTAL=127.0.0.1:15888 \
    ET_WAIT_TIMEOUT=120 \
    ET_POLL_INTERVAL=2 \
    DCGM_EXPORTER_PORT=9400 \
    DCGM_EXPORTER_LISTEN=:9400 \
    DCGM_EXPORTER_COLLECTORS=/etc/dcgm-exporter/default-counters.csv \
    DCGM_EXPORTER_WAIT_TIMEOUT=30 \
    DCGM_EXPORTER_POLL_INTERVAL=1 \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,compat32 \
    NVIDIA_DISABLE_REQUIRE=true \
    NVIDIA_VISIBLE_DEVICES=all

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        ca-certificates \
        curl \
        fontconfig \
        iproute2 \
        jq \
        libgl1 \
        libglib2.0-0 \
        net-tools \
        openssh-server \
        procps \
        tini \
        unzip \
        vim \
        wget; \
    mkdir -p /etc/dcgm-exporter /etc/otelcol /root/.ssh /run/sshd /var/lib/easytier /var/log/easytier; \
    chmod 700 /root/.ssh; \
    case "${TARGETARCH}" in \
        amd64) : ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*;

RUN set -eux; \
    easytier_arch='x86_64'; \
    easytier_sha="${EASYTIER_SHA256_AMD64}"; \
    easytier_zip='/tmp/easytier.zip'; \
    curl -fsSL --retry 3 --output "${easytier_zip}" "https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${easytier_arch}-${EASYTIER_VERSION}.zip"; \
    echo "${easytier_sha}  ${easytier_zip}" | sha256sum -c -; \
    unzip -q "${easytier_zip}" -d /tmp/easytier; \
    install -m 0755 "/tmp/easytier/easytier-linux-${easytier_arch}/easytier-core" /usr/local/bin/easytier-core; \
    install -m 0755 "/tmp/easytier/easytier-linux-${easytier_arch}/easytier-cli" /usr/local/bin/easytier-cli; \
    otel_deb='/tmp/otelcol-contrib.deb'; \
    curl -fsSL --retry 3 --output "${otel_deb}" "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_linux_amd64.deb"; \
    echo "${OTELCOL_CONTRIB_SHA256_AMD64}  ${otel_deb}" | sha256sum -c -; \
    dpkg -i "${otel_deb}"; \
    apt-get purge -y --auto-remove unzip; \
    rm -rf /tmp/easytier "${easytier_zip}" "${otel_deb}" /var/lib/apt/lists/* /var/cache/apt/archives/*;

RUN curl -fsSL --retry 3 --output /usr/local/bin/comfyui-agent https://asset-inc.oss-cn-shanghai.aliyuncs.com/tmp/comfyui-agent; \
    chmod +x /usr/local/bin/comfyui-agent;

# Minimal dcgm-exporter runtime payload copied from NVIDIA's official distroless image:
# - exporter binary
# - default collectors CSV
# - libdcgm client library
# - libdcgmmodule* plugin libraries loaded by libdcgm at runtime
# - libnvperf_dcgm_host.so used by profiling support
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/bin/dcgm-exporter /usr/local/bin/dcgm-exporter
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /etc/dcgm-exporter/default-counters.csv /etc/dcgm-exporter/default-counters.csv
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgm.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgm.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmoduleconfig.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleconfig.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmodulediag.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulediag.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmodulehealth.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulehealth.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmoduleintrospect.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleintrospect.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmodulenvswitch.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulenvswitch.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmodulepolicy.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulepolicy.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmoduleprofiling.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleprofiling.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libdcgmmodulesysmon.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulesysmon.so.4.5.3
COPY --from=dcgm-exporter --chown=0:0 --chmod=0755 /usr/lib/x86_64-linux-gnu/libnvperf_dcgm_host.so /usr/lib/x86_64-linux-gnu/libnvperf_dcgm_host.so

RUN set -eux; \
    chmod 0755 /usr/local/bin/dcgm-exporter; \
    ln -sf libdcgm.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgm.so.4; \
    ln -sf libdcgmmoduleconfig.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleconfig.so.4; \
    ln -sf libdcgmmodulediag.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulediag.so.4; \
    ln -sf libdcgmmodulehealth.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulehealth.so.4; \
    ln -sf libdcgmmoduleintrospect.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleintrospect.so.4; \
    ln -sf libdcgmmodulenvswitch.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulenvswitch.so.4; \
    ln -sf libdcgmmodulepolicy.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulepolicy.so.4; \
    ln -sf libdcgmmoduleprofiling.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmoduleprofiling.so.4; \
    ln -sf libdcgmmodulesysmon.so.4.5.3 /usr/lib/x86_64-linux-gnu/libdcgmmodulesysmon.so.4; \
    ln -sf /etc/dcgm-exporter/default-counters.csv /etc/default-counters.csv

COPY --chmod=0755 docker/easytier-common.sh /usr/local/lib/easytier-common.sh
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/readiness-probe.sh /usr/local/bin/readiness-probe.sh
COPY --chmod=0755 docker/liveness-probe.sh /usr/local/bin/liveness-probe.sh
COPY docker/sshd_config /etc/ssh/sshd_config

EXPOSE 22 9400 11010/tcp 11010/udp

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
