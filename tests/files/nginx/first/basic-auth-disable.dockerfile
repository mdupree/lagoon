ARG UPSTREAM_REPO
ARG UPSTREAM_TAG
FROM ${UPSTREAM_REPO:-testlagoon}/nginx:${UPSTREAM_TAG:-latest}

ENV BASIC_AUTH_USERNAME=username \
    BASIC_AUTH_PASSWORD=password

COPY app/ /app/

# this should disable the basic auth again
COPY .lagoon.env.nginx /app/