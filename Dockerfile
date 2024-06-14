FROM  ubuntu:24.04

ARG RELEASE=112

RUN apt-get update && apt-get -y upgrade
RUN apt-get -y install bioperl git build-essential cpanminus

# Intall base Ensembl API
ARG SRC=/src
RUN mkdir $SRC
WORKDIR $SRC
RUN git clone https://github.com/Ensembl/ensembl-git-tools.git
ENV PATH="${SRC}/ensembl-git-tools/bin:${PATH}"
RUN git ensembl --depth 0 --clone api --branch "release/${RELEASE}"

ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl/modules"
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl-compara/modules"
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl-variation/modules"
ENV PERL5LIB="${PERL5LIB}:${SRC}/ensembl-funcgen/modules"

RUN apt -y install zlib1g-dev
RUN cpanm --installdeps $SRC/ensembl

# Complicated to install Bio::DB::BigFile
# RUN cpanm --installdeps $SRC/ensembl-io
# RUN cpanm --installdeps $SRC/ensembl-metadata
# RUN cpanm --installdeps $SRC/ensembl-compara
# RUN cpanm --installdeps $SRC/ensembl-variation
# RUN cpanm --installdeps $SRC/ensembl-funcgen

# Additional scripts to actually use the API
ADD cpanfile ${SRC}/
RUN cpanm --installdeps $SRC
ENV SCRIPT_DIR=$SRC/scripts
RUN mkdir $SCRIPT_DIR
ADD scripts/* ${SCRIPT_DIR}
ENV PATH="${PATH}:${SCRIPT_DIR}"

# End
# RUN apt-get clean

CMD show_registry.pm

LABEL base.image="ensembl-scripts"
LABEL version="0.1"
LABEL software="EnsEMBL scripts"
LABEL software.version="EnsEMBL scripts for ${RELEASE}"
LABEL about.summary="Ensembl scripts"
LABEL about.home="https://github.com/MatBarba/ensembl-scripts"
LABEL license="Apache 2.0"
LABEL mantainer="Ensembl-Metazoa"
LABEL mantainer.email="ensembl-metazoa@ebi.ac.uk"
