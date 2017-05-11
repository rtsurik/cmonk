.PHONY: all build install

all: 

build:

install:
	install -D -m755 cMonk $(DESTDIR)/usr/lib/cmonk/cMonk
	install -D -m644 cMonkUI.pm $(DESTDIR)/usr/lib/cmonk/cMonkUI.pm
	install -D -m644 modules/nagios.pm $(DESTDIR)/usr/lib/cmonk/modules/nagios.pm
	install -D -m644 modules/zabbix.pm $(DESTDIR)/usr/lib/cmonk/modules/zabbix.pm
	install -D -m644 cmonk.yaml $(DESTDIR)/etc/cmonk.yaml-example
	install -D -m755 cmonk.bin $(DESTDIR)/usr/bin/cmonk
