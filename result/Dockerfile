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
FROM base AS production

ENV NODE_ENV=production
ENV PORT=80

COPY --chown=node:node . .

USER node

EXPOSE 80

ENTRYPOINT ["node", "server.js"]
