# Published CE server image plus the repository files the Coolify stack would otherwise
# bind-mount (Coolify registers repo-file bind mounts as directories). Used by both the
# `setup` and `server` services; build from the commit that matches ALGA_IMAGE_TAG.
ARG ALGA_IMAGE_TAG=43b1f2ec
FROM ghcr.io/nine-minds/alga-psa-ce:${ALGA_IMAGE_TAG}
COPY setup/config.ini /app/setup/config.ini
COPY --chmod=0755 setup/entrypoint.sh /app/setup/entrypoint.sh
COPY --chmod=0755 scripts/coolify/set-admin-password.sh /app/coolify/set-admin-password.sh
