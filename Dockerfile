FROM haskell:9.10.3-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev
WORKDIR /build
RUN cabal update
# Dependencies first: this layer is cached until the cabal or project files change.
# cabal.project* also picks up cabal.project.freeze if you add one later.
COPY paikliin.cabal cabal.project* ./
RUN cabal build --only-dependencies
COPY . .
RUN cabal install exe:paikliin --install-method=copy --installdir=/out --overwrite-policy=always

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 libgmp10 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/paikliin /usr/local/bin/paikliin
COPY migrations /app/migrations
WORKDIR /app
CMD ["paikliin"]

