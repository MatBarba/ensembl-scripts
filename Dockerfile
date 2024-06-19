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
RUN git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl.git
RUN git clone --depth 1 -b release/${RELEASE} https://github.com/Ensembl/ensembl-io.git
RUN cpan -i File::Which # Temporary fix, should be in cpanm
RUN cpanm --quiet --notest --installdeps "$SRC/ensembl"
# This repo cpanfile
ADD cpanfile ${SRC}/
RUN cpanm --quiet --notest --installdeps $SRC

RUN apt -y remove build-essential git && rm -rf /var/lib/apt/lists/*

# Perl and Path variables
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

CMD "show_registry.pl"

LABEL base.image="ensembl-scripts"
LABEL version="0.2"
LABEL software="EnsEMBL scripts"
LABEL software.version="EnsEMBL scripts for ${RELEASE}"
LABEL about.summary="Ensembl API scripts"
LABEL about.home="https://github.com/MatBarba/ensembl-scripts"
LABEL license="Apache 2.0"
LABEL mantainer="Ensembl-Metazoa"
LABEL mantainer.email="ensembl-metazoa@ebi.ac.uk"
