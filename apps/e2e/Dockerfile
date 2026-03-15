FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine

WORKDIR /app

COPY apps/e2e apps/e2e
RUN cd apps/e2e && gleam build

WORKDIR /app/apps/e2e
CMD ["gleam", "run"]
