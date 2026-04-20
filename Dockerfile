FROM debian:trixie-slim

ARG TARGETARCH
ARG EASYTIER_VERSION=v2.4.5
ARG EASYTIER_SHA256_AMD64=d33d1fe6e06fae6155ca7a6ea214657de8d29c4edd5e16fb51f128bef29d3aec
ARG OTELCOL_VERSION=0.150.1
ARG OTELCOL_CONTRIB_SHA256_AMD64=c8ded6c8dbe38e63b63fbfb86b5eff485ba91616254b58ae21dc71d03ba1b922

ENV ET_RPC_PORTAL=127.0.0.1:15888 \
    ET_WAIT_TIMEOUT=120 \
    ET_POLL_INTERVAL=2

COPY docker/easytier-common.sh /usr/local/lib/easytier-common.sh
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/readiness-probe.sh /usr/local/bin/readiness-probe.sh
COPY docker/liveness-probe.sh /usr/local/bin/liveness-probe.sh
COPY docker/sshd_config /etc/ssh/sshd_config

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        iproute2 \
        jq \
        net-tools \
        openssh-server \
        procps \
        tini \
        unzip \
        vim \
        wget; \
    mkdir -p /etc/otelcol /root/.ssh /run/sshd /var/lib/easytier /var/log/easytier; \
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
    chmod 0755 /usr/local/lib/easytier-common.sh /usr/local/bin/entrypoint.sh /usr/local/bin/readiness-probe.sh /usr/local/bin/liveness-probe.sh; \
    apt-get purge -y --auto-remove unzip; \
    rm -rf /tmp/easytier "${easytier_zip}" "${otel_deb}" /var/lib/apt/lists/* /var/cache/apt/archives/*;

EXPOSE 22 11010/tcp 11010/udp

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
