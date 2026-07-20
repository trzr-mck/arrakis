# Smoke-test image for test-app.
#
# This app has no HTTP server — it's a one-shot script that prints a greeting
# and exits. This Dockerfile exists to confirm the workspace installs and the
# entrypoint runs end-to-end, not to "serve" anything long-running.
FROM node:20-alpine

WORKDIR /workspace

RUN corepack enable && corepack prepare pnpm@9 --activate

# Copy manifests first so dependency install is cached independently of
# source changes.
COPY package.json pnpm-workspace.yaml ./
COPY packages/lib/package.json packages/lib/package.json
COPY packages/app/package.json packages/app/package.json

# No pnpm-lock.yaml is committed yet (see README), so this is a plain
# install rather than --frozen-lockfile.
RUN pnpm install

COPY packages ./packages

CMD ["pnpm", "--filter", "test-app", "start"]
