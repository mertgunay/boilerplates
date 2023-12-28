# Since database initialization only happens on container startup, 
# this allows us to set the language before it is created.

# Also of note, Alpine-based variants starting with Postgres 15 support ICU locales.
# Previous Postgres versions based on alpine do not support locales; 
# see "Character sets and locale" in the musl documentation for more details.

# You can set locales in the Alpine-based images with POSTGRES_INITDB_ARGS to set a different locale. 
# The following example will set the default locale for a newly initialized database to de_DE.utf8:

# $ docker run -d 
#    -e LANG=de_DE.utf8 
#    -e POSTGRES_INITDB_ARGS="--locale-provider=icu --icu-locale=de-DE"
#    -e POSTGRES_PASSWORD=mysecretpassword postgres:15-alpine 

FROM postgres:16.1
RUN localedef -i tr_TR -c -f UTF-8 -A /usr/share/locale/locale.alias tr_TR.UTF-8
ENV LANG tr_TR.utf8
