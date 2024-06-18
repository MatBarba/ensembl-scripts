FROM  ubuntu:24.04

ARG RELEASE=112

RUN apt-get update && apt-get -y upgrade
RUN apt-get -y install bioperl git cpanminus
# Needed by ensembl cpanfile
RUN apt -y install build-essential zlib1g-dev
RUN apt -y install genometools
RUN apt-get clean

# Intall base Ensembl API
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

# Perl and Path variables
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl/modules"
ENV PATH="${PATH}:${SRC}/ensembl/misc-scripts/canonical_transcripts"
ENV PATH="${PATH}:${SRC}/ensembl/misc-scripts/meta_coord"
RUN chmod u+x -R "${SRC}/ensembl/misc-scripts"
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl-io/modules"

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
