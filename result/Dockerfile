# Use a supported Node.js LTS runtime
FROM node:22-bookworm-slim AS base

WORKDIR /usr/local/app

# Install the application dependencies from the lockfile
COPY package*.json ./
RUN npm ci && npm cache clean --force

# Development stage
FROM base AS dev

RUN npm install --global nodemon

COPY . .

ENV PORT=80
EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["nodemon", "--inspect=0.0.0.0:9229", "server.js"]

# Production stage
# Official Node images ship npm, yarn, and corepack. Those tools are unused at
# runtime and currently contain HIGH CVEs that fail the Trivy gate, so start
# from a fresh image and copy only the application and its dependencies.
FROM node:22-bookworm-slim AS production

WORKDIR /usr/local/app

ENV NODE_ENV=production
ENV PORT=80

RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/lib/node_modules/corepack \
           /opt/yarn-* \
    && rm -f /usr/local/bin/npm \
             /usr/local/bin/npx \
             /usr/local/bin/corepack \
             /usr/local/bin/yarn \
             /usr/local/bin/yarnpkg

COPY --from=base --chown=node:node /usr/local/app/node_modules ./node_modules
COPY --chown=node:node . .

USER node

EXPOSE 80

ENTRYPOINT ["node", "server.js"]
