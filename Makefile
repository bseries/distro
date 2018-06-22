# Copyright 2014 David Persson. All rights reserved.
# Copyright 2017 Atelier Disko. All rights reserved.
#
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

include Envfile

# Used when building the project, allowed to be overwritten, so external scripts
# may pick a unique or simply different location where they want to process
# the build for themselves without the possibility it being touched by other
# processes.
BUILD_PATH ?= /tmp/build

# Base path for assets, here to make it easy to change.
ASSETS_PATH := app/assets

# Place where all migrations are read from.
MIGRATIONS_PATH := data/upgrade

# Asset directories that need to be linked from modules. Derives scored target versions
# from underscored module name sources to dashed target names.
MODULE_ASSETS := $(shell find app/libraries -type d -name 'assets')
MODULE_ASSETS_LINKS := $(subst _,-,$(patsubst %/,%,$(subst app/libraries/,assets/,$(dir $(MODULE_ASSETS)))))

MODULE_MIGRATIONS := $(shell find app/libraries -type f -path '*/data/upgrade/*.sql')
MODULE_MIGRATIONS_LINKS := $(addprefix $(MIGRATIONS_PATH)/,$(notdir $(MODULE_MIGRATIONS)))

# These files will be checked for translatable strings. When they
# are modified strings will be re-extracted.
EXTRACT_SOURCES := $(shell bash -c "find app/{views,config,documents,models,controllers,extensions,mails} -name '*.php'")

ifeq ($(DB_PASSWORD),)
MYSQL := mysql -u$(DB_USER) -p$(DB_PASSWORD)
else
MYSQL := mysql -u$(DB_USER)
endif

# -- Integrator/Creator --

.PHONY: install
install: prefill app/resources/g11n/cldr app/composer.lock link-assets fix-perms

# Special rule which initializes the Envfile (and other) we just included.
.PHONY: prefill
prefill: 
	sed -i -e "s|__NAME__|$(shell basename $(CURDIR))|g" Hoifile Envfile Deployfile
	sed -i -e "s|__DOMAIN__|$(subst _,-,$(shell basename $(CURDIR))).test|g" Hoifile Envfile
	sed -i -e "s|__SECRET_BASE__|$(shell openssl rand -base64 60 | tr -d '\n')|g" Envfile
	# In Development environments this password is simply empty.
	sed -i -e "s|__DB_PASSWORD__||g" Hoifile Envfile 
	# Some sed leave stray files.
	rm -f Hoifile-e Envfile-e Deployfile-e

app/resources/g11n/cldr: /tmp/cldr_180_core.zip
	unzip -u $< -d /tmp
	cp -r /tmp/common $@

/tmp/cldr_180_core.zip:
	curl http://unicode.org/Public/cldr/1.8.0/core.zip -o /tmp/cldr_180_core.zip 

app/composer.lock:
	composer install -d app

.PHONY: fix-perms
fix-perms:
	chmod -R a+rwX tmp log media media_versions

# --- Assets ---

.PHONY: link-assets
link-assets: assets/app $(MODULE_ASSETS_LINKS)

assets/app:
	ln -s ../app/assets $@

assets/%: | app/composer.lock
	ln -s ../app/libraries/$(subst -,_,$*)/assets $@

# -- Migrations --

.PHONY: link-migrations
link-migrations: $(MODULE_MIGRATIONS_LINKS)

# Derive source name by wildcarding using the stem. There should only ever be
# one match anyway, as we'd otherwise end up with dupes in the target directory,
# that keeps files without any hierachy flattened.
data/upgrade/%: 
	ln -s ../../$(shell find app/libraries -type f -path '*/data/upgrade/*' -name $* -print -quit) $@

# Performs database initialization. Migrations are stored in data/upgrade
# where they can also be picked up by a schema migration tool. 
.PHONY: db-init
db-init: $(MODULE_MIGRATIONS_LINKS)
	find data/upgrade -name "*.sql" -exec sh -c "$(MYSQL) $(DB_DATABASE) < {}" \;

# -- Translations --
#
# To extract translatable strings for translating them (i.e. with POedit) into
# English use the following command. The same command can also be used to update
# the file from source code.
#
# $ make app/resources/g11n/po/en/LC_MESSAGES/default.po

# Extracts strings from source code into PO template.
app/resources/g11n/po/message.pot: $(EXTRACT_SOURCES)
	xgettext $^ -o $@ \
		--sort-by-file \
		--language=PHP \
		--from-code=utf-8 \
		--keyword=t \
		--keyword=tn:1,2 \
		--package-name=$(shell basename $(CURDIR)) \
		--copyright-holder="acme@example.org" \
		--msgid-bugs-address="bugs@example.org"
	sed -i -e 's/CHARSET/UTF-8/' $@
	rm -f $@-e # cleanup stray files

# Initializes an empty or updates an existing PO file. msgmerge cannot init at the same time.
app/resources/g11n/po/%/LC_MESSAGES/default.po: app/resources/g11n/po/message.pot 
	if [ ! -f $@ ]; then msginit -l $* -i $< -o $@ --no-translator; fi
	msgmerge $@ $< -o $@ --verbose

# -- Dist --

# Prepares a copy of the project for distribution under /tmp/dist. When updating
# run dist-clean first.
dist: 
	git clone --verbose --single-branch --recursive --no-hardlinks \
		--branch $(shell git rev-parse --abbrev-ref HEAD) \
		$(CURDIR) $(BUILD_PATH)
	cd $(BUILD_PATH) && bin/build.sh

.PHONY: dist-clean
dist-clean:
	rm -fr $(BUILD_PATH)

# -- Maintainer --

.PHONY: update-assets
update-assets:
	curl https://raw.githubusercontent.com/necolas/normalize.css/master/normalize.css > $(ASSETS_PATH)/css/normalize.css
	curl https://code.jquery.com/jquery-3.2.1.js > $(ASSETS_PATH)/js/jquery.js
	curl http://requirejs.org/docs/release/2.3.2/comments/require.js > $(ASSETS_PATH)/js/require.js
	curl https://raw.githubusercontent.com/requirejs/domReady/latest/domReady.js > $(ASSETS_PATH)/js/require/domready.js
	curl http://underscorejs.org/underscore.js > $(ASSETS_PATH)/js/underscore.js
	curl -L https://raw.githubusercontent.com/zloirock/core-js/master/client/shim.js > $(ASSETS_PATH)/js/compat/core.js
