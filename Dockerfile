# ---- Base stage ----
FROM node:18.20.5-bullseye-slim AS base

# Install system dependencies (no cache mounts for Railway)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        python3 \
        g++ \
        build-essential \
        git \
        poppler-utils \
        poppler-data \
        procps && \
    yarn config set python /usr/bin/python3 && \
    npm install -g node-gyp && \
    npm i -g npm@9.9.3 pnpm@9.15.0 pm2@6.0.10 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV NX_DAEMON=false

# Pre-install commonly reused packages
RUN cd /usr/src && npm i isolated-vm@5.0.1
RUN pnpm store add @tsconfig/node18@1.0.0 @types/node@18.17.1 typescript@4.9.4

# ---- Build stage ----
FROM base AS build
WORKDIR /usr/src/app

COPY .npmrc package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npx nx run-many --target=build --projects=server-api --configuration production
RUN npx nx run-many --target=build --projects=react-ui

RUN cd dist/packages/server/api && npm install --production --force

# ---- Run stage ----
FROM base AS run
WORKDIR /usr/src/app

# Install nginx
RUN apt-get update && apt-get install -y nginx gettext && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY nginx.react.conf /etc/nginx/nginx.conf
COPY packages/server/api/src/assets/default.cf /usr/local/etc/isolate

COPY --from=build /usr/src/app/LICENSE .
RUN mkdir -p /usr/src/app/dist/packages/{server,engine,shared}

COPY --from=build /usr/src/app/dist/packages/engine/ /usr/src/app/dist/packages/engine/
COPY --from=build /usr/src/app/dist/packages/server/ /usr/src/app/dist/packages/server/
COPY --from=build /usr/src/app/dist/packages/shared/ /usr/src/app/dist/packages/shared/

RUN cd /usr/src/app/dist/packages/server/api/ && npm install --production --force
COPY --from=build /usr/src/app/packages packages
COPY --from=build /usr/src/app/dist/packages/react-ui /usr/share/nginx/html/

COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["./docker-entrypoint.sh"]
LABEL service="activepieces"
