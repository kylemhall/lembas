FROM perl:5.40-slim AS deps

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev libmariadb-dev libssl-dev make zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# DBD::MariaDB first: Mojo::mysql picks its driver when it is installed
COPY cpanfile .
RUN cpanm --notest --quiet DBD::MariaDB \
    && cpanm --notest --quiet --installdeps . \
    && rm -rf /root/.cpanm

# The test image: the test dependencies and prettier, the repository is bind mounted (compose.yml)
FROM deps AS test

RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global prettier@3.6.2 \
    && npm cache clean --force

RUN cpanm --notest --quiet --with-feature=test --installdeps . && rm -rf /root/.cpanm

ENV MOJO_MODE=test

# The production image
FROM deps AS app

COPY . .

# The app writes nothing at run time: the files stay owned by root, read by lembas
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin lembas
USER lembas

# docker stop: prefork finishes the requests and workers export their telemetry on SIGQUIT, SIGTERM kills them
STOPSIGNAL SIGQUIT

ARG VERSION=dev
ENV MOJO_MODE=production MOJO_REVERSE_PROXY=1 LEMBAS_BUILD_VERSION=${VERSION}
EXPOSE 8080

# The slim image has no curl, Mojo::UserAgent is already there
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["perl", "-MMojo::UserAgent", "-e", "exit(Mojo::UserAgent->new->get('http://127.0.0.1:8080/health')->res->is_success ? 0 : 1)"]

CMD ["script/lembas", "prefork", "--listen", "http://*:8080"]
