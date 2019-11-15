FROM debian:9 as builder
COPY . /tmp/build
RUN  apt-get update && \
apt-get install -y build-essential debhelper && \
cd /tmp/build && \
dpkg-buildpackage -uc -us -b 

FROM debian:9
COPY --from=builder /tmp/cmonk*_all.deb /tmp/
RUN apt-get update && \
apt-get install -y /tmp/cmonk*_all.deb && \
rm -f /tmp/cmonk*_all.deb && \
apt-get clean
CMD /usr/bin/cmonk
