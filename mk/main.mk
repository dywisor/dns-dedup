DESTDIR     =
PREFIX      = /usr/local
EXEC_PREFIX = $(PREFIX)
BINDIR      = $(EXEC_PREFIX:/=)/bin

EXEMODE ?= 0755
INSMODE ?= 0644
DIRMODE ?= 0755

INSTALL ?= install

RM      ?= rm
RMF      = $(RM) -f

DODIR    = $(INSTALL) -d -m $(DIRMODE)
DOEXE    = $(INSTALL) -D -m $(EXEMODE)
DOINS    = $(INSTALL) -D -m $(INSMODE)

all:

install:
	$(DOEXE) -- $(S)/dns-dedup.pl $(DESTDIR)$(BINDIR)/dns-dedup

uninstall:
	$(RMF) -- $(DESTDIR)$(BINDIR)/dns-dedup


.PHONY: all install uninstall
