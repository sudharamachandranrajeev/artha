# Artha sync server: PocketBase with the Artha schema and sign-up hook.
# The release version and SHA-256 checksums live in pocketbase-version.sh.
FROM alpine:3.22 AS fetch
ARG TARGETARCH
RUN apk add --no-cache curl unzip
WORKDIR /tmp/pb
COPY pocketbase-version.sh /tmp/pb/pocketbase-version.sh
RUN set -eu; \
    . /tmp/pb/pocketbase-version.sh; \
    case "$TARGETARCH" in \
      amd64) sum="$PB_SHA256_amd64" ;; \
      arm64) sum="$PB_SHA256_arm64" ;; \
      *) echo "unsupported architecture: '$TARGETARCH'" >&2; exit 1 ;; \
    esac; \
    zip="pocketbase_${PB_VERSION}_linux_${TARGETARCH}.zip"; \
    curl -fsSLo "$zip" "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/${zip}"; \
    echo "$sum  $zip" | sha256sum -c -; \
    unzip -q "$zip" pocketbase

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata \
 && adduser -D -H -u 10001 artha \
 && mkdir -p /pb/pb_data \
 && chown artha:artha /pb/pb_data
COPY --from=fetch /tmp/pb/pocketbase /pb/pocketbase
COPY pb_migrations /pb/pb_migrations
COPY pb_hooks /pb/pb_hooks
USER artha
WORKDIR /pb
VOLUME /pb/pb_data
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8090/api/health >/dev/null || exit 1
ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090", "--dev=false", "--hooksWatch=false", \
            "--dir=/pb/pb_data", "--migrationsDir=/pb/pb_migrations", "--hooksDir=/pb/pb_hooks"]
