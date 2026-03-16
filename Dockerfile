FROM node:24-slim AS base

WORKDIR /app

COPY package.json package-lock.json ./
COPY prisma ./prisma/

# ------- Dependencies -------
FROM base AS deps

RUN npm ci

# ------- Build ----------
FROM deps AS build

COPY . .

RUN npm run build && cp -r src/generated dist/generated

# ------- Production ------
FROM base AS production

RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

CMD ["node", "dist/index.js"]