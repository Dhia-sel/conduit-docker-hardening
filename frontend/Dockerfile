FROM node:22.12.0-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN npm ci -w frontend

COPY frontend/ frontend/
RUN npm run build -w frontend

FROM nginxinc/nginx-unprivileged:1.28-alpine

LABEL org.opencontainers.image.source="https://github.com/Dhia-sel/conduit-docker-hardening" \
      org.opencontainers.image.licenses="MIT"

COPY --from=build /app/frontend/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1