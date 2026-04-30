# PostgreSQL with the tr_TR.UTF-8 locale baked in.
#
# We use the Debian-based image (not Alpine) because adding non-default
# locales on Alpine + musl is brittle. The Debian image already has
# locale-gen tooling.
#
# Why this matters: Postgres locks the database cluster locale at initdb
# time. To use Turkish collation/sorting (LC_COLLATE=tr_TR.UTF-8),
# tr_TR.UTF-8 must exist on the OS BEFORE the cluster is initialized.
#
# To use a different locale, change LANG and the localedef line.

FROM postgres:17

RUN localedef -i tr_TR -c -f UTF-8 -A /usr/share/locale/locale.alias tr_TR.UTF-8
ENV LANG=tr_TR.UTF-8
