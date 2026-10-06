FROM node:alpine
COPY package.json ,  package-lock.json , frontend/package.json .
WORKDIR /app
RUN npm ci
HEALTHCHECK docker inspect
