# ---- build stage -----------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# ---- runtime stage ----------------------------------------------------------
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY migrations ./migrations
RUN mkdir -p /app/uploads && chown -R node:node /app
USER node
EXPOSE 8080
CMD ["node", "dist/index.js"]
