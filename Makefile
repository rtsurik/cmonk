.PHONY: all build install

all: 

build:

install:
	install -D -m755 cmonk-cui.pl $(DESTDIR)/usr/lib/cmonk/cmonk-cui.pl
	install -D -m644 cMonkUI.pm $(DESTDIR)/usr/lib/cmonk/cMonkUI.pm
	install -D -m644 modules/nagios.pm $(DESTDIR)/usr/lib/cmonk/modules/nagios.pm
	install -D -m644 modules/zabbix2.pm $(DESTDIR)/usr/lib/cmonk/modules/zabbix2.pm
	install -D -m644 cmonk.yaml $(DESTDIR)/etc/cmonk.yaml-example
	install -D -m755 cmonk.bin $(DESTDIR)/usr/bin/cmonk
