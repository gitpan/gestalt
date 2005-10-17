[% DEFAULT APP_NAME='mySpiffyApp' -%]
[% DEFAULT EMAIL='bradley@kitefamily.co.uk' -%]

[%- IF TOP_LEVEL -%]
SUBDIRS = DB Apache templates html
[% END -%]

[%- IF DB -%]
SUBDIRS = Table
[% END -%]

[%- IF APACHE -%]
SUBDIRS = Request
[% END -%]

[%- IF REQUEST -%]
SUBDIRS = Controller
[% END -%]

[%- IF BASE && ( ROW || TABLE || CONTROLLER || TEMPLATE ) -%]
SUBDIRS = [% IF TABLE %]Row [% END %][% FOREACH tableName = TABLES %][% tableName %][% UNLESS loop.last %] [% END %][% END %]
[% IF TEMPLATE -%]

templatedir=$(prefix)/[% APP_NAME %]/templates
template_DATA = _header.tt2 \
                _fieldDisplay.tt2 \
                _fieldInput.tt2 \
                _fkeyDisplay.tt2 \
                _fkeyInput.tt2 \
                _pager.tt2 \
                _form.tt2
EXTRA_DIST = $(template_DATA)
[% END -%]
[% END -%]

[%- IF (!BASE) && (ROW || TABLE || CONTROLLER) -%]
moduledir=$(prefix)/modules/[% IF ROW %]DB/Table/Row[% ELSIF TABLE %]DB/Table[% ELSIF CONTROLLER %]Apache/Request/Controller[% END %]
module_DATA = [% tableName %].pm
EXTRA_DIST = $(module_DATA)
[% END -%]

[%- IF (!BASE) && TEMPLATE -%]
templatedir=$(prefix)/[% APP_NAME %]/templates/[% tableName %]
template_DATA = list.tt2 \
                show.tt2 \
                create.tt2 \
                edit.tt2
EXTRA_DIST = $(template_DATA)
[% END -%]

[% IF TOP_LEVEL -%]

cfgdir=$(prefix)/[% APP_NAME %]
cfg_DATA = [% APP_NAME %].cfg


apacheconfdir=/etc/httpd/conf.d
apacheconf_DATA = [% APP_NAME %].apache.conf \
                  [% APP_NAME %].pl

EXTRA_DIST = $(cfg_DATA) $(apacheconf_DATA)

rpm: dist
	cp [% APP_NAME %]-$(VERSION).tar.gz /usr/src/redhat/SOURCES/
	rpmbuild -ba [% APP_NAME %].spec
	cp /usr/src/redhat/SRPMS/[% APP_NAME %]-$(VERSION)-1.src.rpm .
	cp /usr/src/redhat/RPMS/noarch/[% APP_NAME %]-$(VERSION)-1.noarch.rpm .
[% END -%]
