FROM docker.io/golang:1.26.10-bookworm@sha256:fe3da92a5cb2881e4aa75e625cb0b7c50571632fb4cf340cbe53e6ccdcffdd51 AS tests

# gno v1.7.0, the release gno.land's mainnet runs, with the standard-library
# changes of gno's draft pull request that adds crypto/secp256k1.RecoverPubkey,
# which the realms call: its head, and the gno commit it is based on. All three
# commits come from gno's repository.
ARG GNO_RELEASE=e4c2e7d9fe0f6f7aeeda54885ca1fe5cea991319
ARG GNO_DRAFT_BASE=2ed70a202e6f92364be56c5c17ddd706e0c9d922
ARG GNO_DRAFT_HEAD=0801e9e4d2205840216a040c15a640feb972edbe

RUN git init -q /gno \
 && cd /gno \
 && git fetch -q --depth 1 https://github.com/gnolang/gno.git "$GNO_RELEASE" "$GNO_DRAFT_BASE" "$GNO_DRAFT_HEAD" \
 && git checkout -q "$GNO_RELEASE" \
 && git diff "$GNO_DRAFT_BASE" "$GNO_DRAFT_HEAD" -- gnovm/stdlibs | git apply --3way \
 && go build -o /usr/local/bin/gno ./gnovm/cmd/gno

COPY . /src
WORKDIR /src

RUN --network=none GNOROOT=/gno python3 scripts/test.py
