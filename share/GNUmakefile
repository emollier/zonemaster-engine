.POSIX:
.SUFFIXES: .po .mo
.PHONY: all check-msg-args dist extract-pot tidy-po show-fuzzy update-po new-po check-po

POFILES := $(shell find . -maxdepth 1 -type f -name '*.po' -exec basename {} \;)
MOFILES := $(POFILES:%.po=%.mo)
POTFILE = Zonemaster-Engine.pot
PMFILES := $(shell find ../lib -type f -name '*.pm' | sort)
TESTMODULEFILES := $(shell find ../lib/Zonemaster/Engine/Test -type f -name '*.pm' | sort)

all: $(MOFILES) modules.txt

# Tidy the formatting of all PO files
tidy-po:
	@tmpdir="`mktemp -d tidy-po.XXXXXXXX`" ;\
	trap 'rm -rf "$$tmpdir"' EXIT ;\
	for f in $(POFILES) ; do msgcat $$f -o $$tmpdir/$$f && mv -f $$tmpdir/$$f $$f  ; done

update-po: extract-pot
	@for f in $(POFILES) ; do msgmerge --update --backup=none --quiet --no-location $(MSGMERGE_OPTS) $$f $(POTFILE) ; done

extract-pot:
	@xgettext --output $(POTFILE) --sort-by-file --add-comments --language=Perl --from-code=UTF-8 -k__ -k\$$__ -k%__ -k__x -k__n:1,2 -k__nx:1,2 -k__xn:1,2 -kN__ -kN__n:1,2 -k__p:1c,2 -k__np:1c,2,3 -kN__p:1c,2 -kN__np:1c,2,3 $(PMFILES)

$(POTFILE): extract-pot

# Create a new empty PO file with basename provided with the POLANG variable
# Update the Language field in the header
new-po: extract-pot
	@[ -n "$(POLANG)" ] || ( echo "Usage: make POLANG=xx new-po" && exit 1 )
	@cp $(POTFILE) $(POLANG).po
	@perl -pi -e 's/^("Project-Id-Version:) .+(\\n)/$$1 1.0.0$$2/;' \
		-e 's/^("Language-Team:) .+(\\n)/$$1 Zonemaster Team$$2/;' \
		-e 's/^"Language: /$$&$(POLANG)/;' \
		-e 's/^("Content-Type:.+charset=)CHARSET/$${1}UTF-8/;' $(POLANG).po
	@perl -ni -e 'print unless /^#( |$$)/' $(POLANG).po

check-po:
	@for f in $(POFILES) ; do msgfmt -c $$f ; done

.po.mo:
	@msgfmt -o $@ $<
	@mkdir -p locale/`basename $@ .mo`/LC_MESSAGES
	@ln -vf $@ locale/`basename $@ .mo`/LC_MESSAGES/Zonemaster-Engine.mo

show-fuzzy:
	@for f in $(POFILES) ; do msgattrib --only-fuzzy $$f ; done

check-msg-args:
	@for f in $(POFILES) ; do ../util/check-msg-args $$f ; done

modules.txt: $(TESTMODULEFILES)
	@echo Basic > modules.txt
	@echo $(TESTMODULEFILES) | xargs basename -s .pm -a | grep -vE '^Basic$$' | sort >> modules.txt
