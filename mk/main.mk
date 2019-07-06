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

X_PERLCRITIC = perlcritic
PERLCRITIC_OPTS  =
PERLCRITIC_OPTS += --brutal
PERLCRITIC_OPTS += --verbose 11
PERLCRITIC_OPTS += --exclude ProhibitMultiplePackages
PERLCRITIC_OPTS += --exclude ProhibitPunctuationVars
PERLCRITIC_OPTS += --exclude RequireDotMatchAnything
PERLCRITIC_OPTS += --exclude RequireTidyCode

all:

install:
	$(DOEXE) -- $(S)/dns-dedup.pl $(DESTDIR)$(BINDIR)/dns-dedup

uninstall:
	$(RMF) -- $(DESTDIR)$(BINDIR)/dns-dedup

check:
	$(X_PERLCRITIC) $(PERLCRITIC_OPTS) $(S)/dns-dedup.pl


.PHONY: all install uninstall check
