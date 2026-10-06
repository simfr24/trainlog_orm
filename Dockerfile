# The `orm` tile cache, plus upstream's style.json so Trainlog never has to ask
# openrailwaymap.app for anything. `upstream` is the OpenRailwayMap-vector repo, passed
# in as an additional build context (docker-compose.yml), the same commit Martin is built
# from. Mirrors the build-styles stage of upstream's proxy.Dockerfile.
FROM node:24-alpine AS style

WORKDIR /build

RUN npm install yaml@2.8.1

RUN --mount=type=bind,from=upstream,source=proxy/js/styles.mjs,target=styles.mjs \
  --mount=type=bind,from=upstream,source=features,target=features \
  node styles.mjs \
    > style.json

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=style /build/style.json /usr/share/nginx/orm/style.json
