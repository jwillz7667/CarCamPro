# syntax=docker/dockerfile:1.7
# Multi-stage build — deps install under non-root, runtime slim.

# ───── Base: lock Node + pnpm versions ─────
FROM node:22-alpine AS base
ENV PNPM_HOME=/pnpm
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@9.14.4 --activate

WORKDIR /app

# ───── Deps: install cached, run prisma generate ─────
FROM base AS deps
COPY package.json pnpm-lock.yaml* ./
COPY prisma ./prisma
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile --prod=false && \
    pnpm prisma generate

# ───── Build: TypeScript → dist ─────
FROM deps AS build
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN pnpm build && pnpm prune --prod

# ───── Runtime: slim, non-root ─────
FROM node:22-alpine AS runtime
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app

# Prisma needs the engine binaries; copy only those from the build stage.
COPY --from=build --chown=app:app /app/node_modules ./node_modules
COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/package.json ./package.json
COPY --from=build --chown=app:app /app/prisma ./prisma

ENV NODE_ENV=production
USER app
EXPOSE 4000

# A bare-bones healthcheck — Railway + Fly both respect this.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4000/health/ready || exit 1

CMD ["node", "dist/server.js"]
