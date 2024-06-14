FROM  ubuntu:24.04

ENV RELEASE=112

RUN apt-get update && apt-get -y upgrade
RUN apt-get -y install bioperl git
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Intall base Ensembl API
ENV SRC=/src
RUN mkdir $SRC
WORKDIR $SRC
RUN git clone https://github.com/Ensembl/ensembl-git-tools.git
ENV PATH="${SRC}/ensembl-git-tools/bin:${PATH}"
RUN git ensembl --depth 0 --clone api --branch "release/${RELEASE}"

ENV PERL5LIB="${SRC}/src/ensembl/modules"
ENV PERL5LIB="${SRC}/src/ensembl-compara/modules"
ENV PERL5LIB="${SRC}/src/ensembl-variation/modules"
ENV PERL5LIB="${SRC}/src/ensembl-funcgen/modules"
#ADD script.sh /usr/local/bin/

CMD ["datasets --version"]

LABEL base.image="ensembl-scripts"
LABEL version="0.1"
LABEL software="EnsEMBL scripts"
LABEL software.version="EnsEMBL scripts for ${RELEASE}"
LABEL about.summary="Ensembl scripts"
LABEL about.home="https://github.com/MatBarba/ensembl-scripts"
LABEL license="Apache 2.0"
LABEL mantainer="Ensembl-Metazoa"
LABEL mantainer.email="ensembl-metazoa@ebi.ac.uk"
