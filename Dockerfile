# syntax=docker/dockerfile:1
FROM alpine:3.24 AS fetch
# renovate: datasource=github-releases depName=suzuki-shunsuke/ghproj
ARG GHPROJ_VERSION=v1.0.1
ARG TARGETARCH
RUN apk add --no-cache cosign
WORKDIR /fetch
ADD https://github.com/suzuki-shunsuke/ghproj/releases/download/${GHPROJ_VERSION}/ghproj_${GHPROJ_VERSION#v}_checksums.txt \
    https://github.com/suzuki-shunsuke/ghproj/releases/download/${GHPROJ_VERSION}/ghproj_${GHPROJ_VERSION#v}_checksums.txt.sigstore.json \
    https://github.com/suzuki-shunsuke/ghproj/releases/download/${GHPROJ_VERSION}/ghproj_linux_${TARGETARCH}.tar.gz \
    ./
# ghproj's releases are signed by a release workflow its author shares across projects, so the
# identity alone would also accept another project's release; the repository and tag pin it to
# this one.
RUN cosign verify-blob \
      --bundle "ghproj_${GHPROJ_VERSION#v}_checksums.txt.sigstore.json" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity-regexp '^https://github\.com/suzuki-shunsuke/go-release-workflow/\.github/workflows/release\.yaml@' \
      --certificate-github-workflow-repository suzuki-shunsuke/ghproj \
      --certificate-github-workflow-ref "refs/tags/${GHPROJ_VERSION}" \
      "ghproj_${GHPROJ_VERSION#v}_checksums.txt" \
 && grep " ghproj_linux_${TARGETARCH}.tar.gz\$" "ghproj_${GHPROJ_VERSION#v}_checksums.txt" > archive.sha256 \
 && sha256sum -c archive.sha256 \
 && tar -xzf "ghproj_linux_${TARGETARCH}.tar.gz" ghproj

FROM alpine:3.24
RUN apk add --no-cache curl jq openssl
COPY --from=fetch /fetch/ghproj /usr/local/bin/ghproj
COPY entrypoint /usr/local/bin/entrypoint
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/entrypoint"]
