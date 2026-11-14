# Build from a trusted copy of the board (git archive), never the ticket diff.
FROM node:22-alpine AS node22
FROM python:3.12-alpine3.24
RUN apk add --no-cache git elixir erlang-dev erlang-dialyzer postgresql18 postgresql18-client libstdc++ make gcc musl-dev github-cli openssh-client rebar3 coreutils zstd procps-ng sqlite bash jq ripgrep tmux curl && adduser -D -u 1001 worker
COPY --from=node22 /usr/local/bin/node /usr/local/bin/node
COPY --from=node22 /usr/local/lib/node_modules/npm /opt/npm
COPY priv/agent/harness/package*.json /opt/harness/
COPY priv/agent/check-alpine-harness.cjs /opt/harness/
RUN ln -s /opt/npm/bin/npm-cli.js /usr/local/bin/npm && cd /opt/harness && npm ci --no-audit --no-fund && ln -s /opt/harness/node_modules/.bin/dsh /usr/local/bin/dsh && node check-alpine-harness.cjs /usr/local/bin/dsh
ENV MIX_HOME=/opt/board-mix MIX_ARCHIVES=/opt/board-mix/archives MIX_REBAR3=/usr/bin/rebar3
WORKDIR /build
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix deps.get --check-locked && mv deps /opt/board-deps
# elixir_make uses the checksums provided by the locked package when it extracts the NIF.
RUN set -eu; case "$(apk --print-arch)" in aarch64|x86_64) arch=$(apk --print-arch);; *) exit 1;; esac; \
    mkdir /opt/board-cache; cd /opt/board-cache; \
    for spec in 'dashbitco/lazy_html lazy_html 0.1.14 2.16' 'elixir-sqlite/exqlite exqlite 0.43.0 2.17'; do \
      set -- $spec; file="$2-nif-$4-$arch-linux-musl-$3.tar.gz"; \
      curl -fLsS "https://github.com/$1/releases/download/v$3/$file" -o "$file"; \
      grep -F "$(sha256sum "$file" | cut -d' ' -f1)" "/opt/board-deps/$2/checksum.exs" >/dev/null; done
COPY ops/container-worker/board-publication-check /usr/local/bin/board-publication-check
ENV HEX_OFFLINE=1 HEX_NO_UPDATE_CHECK=1 MIX_BUILD_PATH=/tmp/board-build MIX_DEPS_PATH=/workspace/deps ERL_FLAGS="+S 4:4" HOME=/home/worker
USER worker
WORKDIR /workspace
