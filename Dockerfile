FROM debian:trixie-slim

ARG TARGETARCH
ARG EASYTIER_VERSION=v2.4.5
ARG EASYTIER_SHA256_AMD64=d33d1fe6e06fae6155ca7a6ea214657de8d29c4edd5e16fb51f128bef29d3aec
ARG EASYTIER_SHA256_ARM64=df08c842f2ab2b8e9922f13c686a1d0f5a5219775cfdabb3e4a8599c6772201f
ARG OTELCOL_VERSION=0.150.1
ARG OTELCOL_SHA256_AMD64=bab7659b8c2587b1d9c099c7902d57ceff45300efa9d62fc5a188c39b7b02dda
ARG OTELCOL_SHA256_ARM64=c0a669b670b64b41f46d4baa806eac3a542022fcabf51814916e2496b9fc6011

ENV ET_RPC_PORTAL=127.0.0.1:15888 \
    ET_WAIT_TIMEOUT=120 \
    ET_POLL_INTERVAL=2

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
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
        amd64) easytier_arch='x86_64'; easytier_sha="${EASYTIER_SHA256_AMD64}"; otel_arch='amd64'; otel_sha="${OTELCOL_SHA256_AMD64}" ;; \
        arm64) easytier_arch='aarch64'; easytier_sha="${EASYTIER_SHA256_ARM64}"; otel_arch='arm64'; otel_sha="${OTELCOL_SHA256_ARM64}" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    easytier_zip='/tmp/easytier.zip'; \
    curl -fsSL --retry 3 --output "${easytier_zip}" "https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${easytier_arch}-${EASYTIER_VERSION}.zip"; \
    echo "${easytier_sha}  ${easytier_zip}" | sha256sum -c -; \
    unzip -q "${easytier_zip}" -d /tmp/easytier; \
    install -m 0755 /tmp/easytier/easytier-core /usr/local/bin/easytier-core; \
    install -m 0755 /tmp/easytier/easytier-cli /usr/local/bin/easytier-cli; \
    otel_deb='/tmp/otelcol.deb'; \
    curl -fsSL --retry 3 --output "${otel_deb}" "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol_${OTELCOL_VERSION}_linux_${otel_arch}.deb"; \
    echo "${otel_sha}  ${otel_deb}" | sha256sum -c -; \
    dpkg -i "${otel_deb}"; \
    apt-get purge -y --auto-remove unzip; \
    chmod 0755 /usr/local/bin/entrypoint.sh; \
    rm -rf /tmp/easytier "${easytier_zip}" "${otel_deb}" /var/lib/apt/lists/* /var/cache/apt/archives/*;

EXPOSE 22 11010/tcp 11010/udp

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
