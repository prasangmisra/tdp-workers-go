FROM postgres:14-bookworm

LABEL maintainer="Tucows Domains"

RUN apt-get update \
    && apt install -y postgresql-14-cron postgresql-14-pgtap build-essential\
    && rm -rf /var/lib/apt/lists/*

COPY script script
