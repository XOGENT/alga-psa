# Pinned pgvector image plus the repository scripts the Coolify stack would otherwise
# bind-mount (Coolify registers repo-file bind mounts as directories).
ARG ALGA_PGVECTOR_IMAGE=pgvector/pgvector:0.8.7-pg15-bookworm@sha256:47af0b65960b14f1c6945aa4ccae37836c632e9a6fe0eea9160936e616e5b2e9
FROM ${ALGA_PGVECTOR_IMAGE}
COPY postgres/alga-postgres-entrypoint.sh /usr/local/bin/alga-postgres-entrypoint.sh
COPY helm/files/postgres/update-extensions.sh /opt/alga/update-extensions.sh
