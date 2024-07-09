FROM  ubuntu:24.04

ARG RELEASE=112

RUN apt-get update && apt-get -y upgrade \
    && apt -y install \
        bioperl \
        git \
        cpanminus \
        # Needed by ensembl cpanfile
        build-essential \
        zlib1g-dev \
        # Extra to use gt
        genometools \
        # mysql_config for DBD::mysql
        libmariadb-dev-compat \
        && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install base Ensembl API
ARG SRC=/src
RUN mkdir $SRC
WORKDIR $SRC

# ensembl
RUN git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl.git && rm -fr ensembl/.git ensembl/modules/t
RUN cpan -i File::Which # Temporary fix, should be in cpanm
RUN cpanm --quiet --notest --installdeps "$SRC/ensembl"

# ensembl-io
RUN NAME=io && git clone --depth 1 https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t
# Requires Kent tree for BigFile
RUN git clone --depth 1 https://github.com/ucscGenomeBrowser/kent.git
# WORKDIR "$SRC/kent/src"
# ENV MACHTYPE="x86_64"
# RUN make topLibs
# FAILING: missing png.h (libpng-dev not available anymore in Ubuntu?)
# Next step should set an ENV to jkweb.a (and remove the whole SRC)
# RUN mv jkweb.a $SRC/lib
# ENV JKWEB=$SRC/lib/
# RUN cpanm --quiet --notest --installdeps "$SRC/ensembl-io"

RUN NAME=analysis && git clone --depth 1 https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t
#  Can't build  Bio-DB-HTS without htslib, needs to built from kent source as well tree
# ENV HTSLIB_DIR="$SRC/kent/src/htslib/htslib"
# RUN cpanm --quiet --notest --installdeps "$SRC/ensembl-analysis"

# Other repos
RUN NAME=production && git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t
RUN NAME=production-imported && git clone --depth 1 -b main https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t
RUN NAME=compara && git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t
RUN NAME=funcgen && git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl-${NAME}.git && rm -fr ensembl-${NAME}/.git ensembl-${NAME}/modules/t

# This repo cpanfile
ADD cpanfile ${SRC}/
RUN cpanm --quiet --notest --installdeps $SRC

# Clean up extra libs
RUN apt autoremove
RUN apt -y remove build-essential git && rm -rf /var/lib/apt/lists/*

# Perl and Path variables
ENV PERL5LIB="."
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl/modules"
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl-io/modules"
ENV PATH="${PATH}:${SRC}/ensembl/misc-scripts/canonical_transcripts"
ENV PATH="${PATH}:${SRC}/ensembl/misc-scripts/meta_coord"
RUN chmod u+x -R "${SRC}/ensembl/misc-scripts"

# Additional scripts to actually use the API
ENV SCRIPT_DIR=$SRC/scripts
RUN mkdir $SCRIPT_DIR
ADD scripts/* ${SCRIPT_DIR}
ENV PATH="${PATH}:${SCRIPT_DIR}"

CMD ["show_registry.pl"]

LABEL base.image="ensembl-scripts"
LABEL version="0.2"
LABEL software="EnsEMBL scripts"
LABEL software.version="EnsEMBL scripts for ${RELEASE}"
LABEL about.summary="Ensembl API scripts"
LABEL about.home="https://github.com/MatBarba/ensembl-scripts"
LABEL license="Apache 2.0"
LABEL mantainer="Ensembl-Metazoa"
LABEL mantainer.email="ensembl-metazoa@ebi.ac.uk"
