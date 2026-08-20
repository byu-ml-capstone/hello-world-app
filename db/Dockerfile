# Tiny Dockerfile that bakes our schema-init SQL into a custom postgres
# image. Two-line wrap around the official image; the only reason we
# build our own instead of using `image: postgres:16-alpine` directly
# plus a bind-mount is that Coolify's git-checkout-to-/artifacts flow
# doesn't always make bind-mount sources visible to the container
# runtime — a COPY happens at image-build time on the same host, so it
# always works.
FROM postgres:16-alpine

# The official postgres image auto-executes any *.sql / *.sh in
# /docker-entrypoint-initdb.d/ on FIRST startup (empty data directory).
COPY init.sql /docker-entrypoint-initdb.d/init.sql
