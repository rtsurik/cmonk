.PHONY: all build install

all: 

build:

install:
	install -D -m755 cMonk $(DESTDIR)/usr/lib/cmonk/cMonk
	install -D -m644 cMonkUI.pm $(DESTDIR)/usr/lib/cmonk/cMonkUI.pm
	install -D -m644 plugins/nagios.pm $(DESTDIR)/usr/lib/cmonk/plugins/nagios.pm
	install -D -m644 plugins/zabbix.pm $(DESTDIR)/usr/lib/cmonk/plugins/zabbix.pm
	install -D -m644 cMonk.config $(DESTDIR)/etc/cMonk.config-example
	install -D -m755 cmonk.bin $(DESTDIR)/usr/bin/cmonk
