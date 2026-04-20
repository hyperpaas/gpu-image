# Repository Guidelines

## Scope
- This repository maintains Docker images for the compute platform and the GitHub Actions workflow that builds and publishes them.
- The image must be buildable directly from this repository on GitHub Actions and publishable to GitHub Container Registry (GHCR).

## Hard Requirements
- Base image must be `debian:trixie-slim`.
- Keep the final image as simple and thin as practical:
  - prefer fewer `RUN` layers when it does not significantly harm maintainability;
  - combine related package install / download / verify / cleanup steps.
- Every installation flow must end with cleanup:
  - remove downloaded archives and temporary extraction directories;
  - remove apt lists and caches;
  - do not leave unused build artifacts in the image.
- Everything required by GitHub Actions must live in this repository.
- External downloads are allowed only from official or otherwise clearly trusted sources, and must be integrity-checked when feasible.

## Runtime Requirements
- Install and use `tini` as the container init process.
- Install `openssh-server` and configure root login to allow **public key auth only**.
- Install OpenTelemetry Collector (`otelcol`).
- Install EasyTier core and client (`easytier-core`, `easytier-cli`).
- Install basic tools such as `curl`, `wget`, and `vim`.
- Container startup order must be:
  1. validate required EasyTier environment variables;
  2. start EasyTier;
  3. wait for EasyTier readiness / network join success;
  4. start `openssh-server` and `otelcol`.
- Startup must fail fast when either `ET_NETWORK_NAME` or `ET_NETWORK_SECRET` is missing.
- The OpenTelemetry Collector config path must remain stable at `/etc/otelcol/config.yaml` so Kubernetes can mount a ConfigMap there.

## Security / Supply Chain
- Prefer official release artifacts:
  - EasyTier: `https://github.com/EasyTier/EasyTier/releases`
  - OpenTelemetry Collector: `https://github.com/open-telemetry/opentelemetry-collector-releases/releases`
- Pin versions in the Dockerfile with explicit build arguments.
- Verify downloaded artifacts with pinned SHA-256 values before installing.
- Do not introduce password-based SSH login.

## GitHub Actions Publishing Policy
- Publish images to `ghcr.io/<owner>/<repo>`.
- Build images for `linux/amd64`.
- Tag rules:
  - push to default branch: publish `latest`, default branch name tag (for example `main`), and `sha-<shortsha>`;
  - push to non-default branches: publish branch name tag and `sha-<shortsha>`;
  - push Git tag matching semver `vX.Y.Z`: publish `X.Y.Z`, `X.Y`, `X`, and `sha-<shortsha>`.
- Pull requests may build for validation, but should not push images.

## Change Expectations For Future Agents
- Preserve the startup contract and environment-variable-driven EasyTier behavior.
- Preserve `/etc/otelcol/config.yaml` unless the user explicitly requests a path change.
- Preserve SSH public-key-only root access.
- If versions are updated, update both version pins and checksum pins together.
- If workflow tagging behavior changes, update this file in the same change.
