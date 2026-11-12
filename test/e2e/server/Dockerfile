FROM ubuntu:24.04

ARG TT_VERSION=5.23
ARG TT_SHA256=880aac9610ccd1ca8f13c1dfcb32dede149de13fc84f8a6b8e2ca059b1aa1ea4
ARG TT_PRO_SHA256=4a8bca219ad371541c44e641afe9d17cd2acaef3724b05b1cee291dea21b2986

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl openssl stunnel4 \
 && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    base="https://bearware.dk/teamtalk/v${TT_VERSION}"; \
    pkg="teamtalk-v${TT_VERSION}-ubuntu24-x86_64"; \
    pro="teamtalkpro-v${TT_VERSION}-ubuntu24-x86_64"; \
    curl -fsSL -o /tmp/tt.tgz "${base}/${pkg}.tgz"; \
    curl -fsSL -o /tmp/ttpro.tgz "${base}/${pro}.tgz"; \
    echo "${TT_SHA256}  /tmp/tt.tgz" | sha256sum -c -; \
    echo "${TT_PRO_SHA256}  /tmp/ttpro.tgz" | sha256sum -c -; \
    tar xzf /tmp/tt.tgz -C /tmp "${pkg}/server/tt5srv" "${pkg}/License.txt"; \
    tar xzf /tmp/ttpro.tgz -C /tmp "${pro}/server/tt5prosrv"; \
    install -m 0755 "/tmp/${pkg}/server/tt5srv" /usr/local/bin/tt5srv; \
    install -m 0755 "/tmp/${pro}/server/tt5prosrv" /usr/local/bin/tt5prosrv; \
    install -D -m 0644 "/tmp/${pkg}/License.txt" \
      /usr/local/share/teamtalk/License.txt; \
    rm -rf /tmp/tt.tgz /tmp/ttpro.tgz "/tmp/${pkg}" "/tmp/${pro}"

RUN useradd --system --home-dir /srv/teamtalk --create-home teamtalk
WORKDIR /srv/teamtalk

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tt5srv.xml stunnel.conf /srv/teamtalk/

RUN openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj "/CN=teamtalkx-e2e" \
      -keyout /srv/teamtalk/ttserverkey.pem \
      -out /srv/teamtalk/ttservercert.pem \
 && chown -R teamtalk:teamtalk /srv/teamtalk

USER teamtalk
EXPOSE 10333/tcp 10333/udp 10443/tcp 10543/tcp 10543/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
