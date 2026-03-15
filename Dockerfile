FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine AS builder

WORKDIR /app

# Copy shared first (dependency of both)
COPY apps/shared apps/shared

# Build client
COPY apps/client apps/client
RUN cd apps/client && gleam build

# Bundle client JS with esbuild
RUN apk add --no-cache npm && npm install -g esbuild
RUN esbuild apps/client/build/dev/javascript/client/client.mjs \
    --bundle --outfile=/app/client.mjs --format=esm

# Build server
COPY apps/server apps/server
RUN cd apps/server && gleam build

# Runtime
FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine

WORKDIR /app/apps/server
COPY --from=builder /app/apps/shared /app/apps/shared
COPY --from=builder /app/apps/server /app/apps/server
COPY --from=builder /app/client.mjs /app/client.mjs

ENV CLIENT_JS_PATH=/app/client.mjs

CMD ["gleam", "run"]
