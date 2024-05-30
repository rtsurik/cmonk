FROM debian:11 as builder
COPY . /tmp/build
RUN  apt-get update && \
apt-get install -y build-essential debhelper && \
cd /tmp/build && \
dpkg-buildpackage -uc -us -b 

FROM debian:11
COPY --from=builder /tmp/cmonk*_all.deb /tmp/
COPY rpc_client_remove_version.diff /tmp/
RUN apt-get update && \
apt-get install -y /tmp/cmonk*_all.deb && \
rm -f /tmp/cmonk*_all.deb && \
apt-get install -y patch && \
patch /usr/share/perl5/JSON/RPC/Legacy/Client.pm /tmp/rpc_client_remove_version.diff && \
apt-get clean
CMD /usr/bin/cmonk
