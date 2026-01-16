# 🐳 Dockerfile per ICV HF Application
# Build ottimizzato per Koyeb Free Tier con Alpine

# ===== FASE DI BUILD =====
FROM node:20-alpine AS builder

# Installa dipendenze di sistema per build
RUN apk update && apk add --no-cache \
    git \
    python3 \
    make \
    g++ \
    ffmpeg \
    && rm -rf /var/cache/apk/*

# Imposta directory di lavoro
WORKDIR /app

# Clona il repository ICV HF
ARG REPO_URL=https://github.com/qwertyuiop8899/icv_hf.git
ARG BRANCH=main
RUN git clone --depth 1 --single-branch --branch ${BRANCH} ${REPO_URL} . \
    && rm -rf .git

# Verifica struttura del progetto
RUN echo "📁 Struttura progetto:" && ls -la

# Installa dipendenze Node.js con ottimizzazioni per memoria limitata
RUN npm config set maxsockets 1 \
    && npm config set fetch-retry-maxtimeout 60000 \
    && npm config set fetch-retry-mintimeout 10000

# Installa dipendenze di produzione
RUN npm ci --only=production --no-audit --no-fund --prefer-offline \
    && npm cache clean --force

# ===== FASE DI RUNTIME =====
FROM node:20-alpine

# Metadati
#LABEL maintainer="icv-hf@example.com"
LABEL version="1.0.0"
LABEL description="ICV HF Application for Koyeb Free Tier"

# Installa runtime dependencies (solo ffmpeg necessario)
RUN apk update && apk add --no-cache \
    ffmpeg \
    tini \
    && rm -rf /var/cache/apk/*

# Crea utente non-root per sicurezza
RUN addgroup -g 1001 -S appuser \
    && adduser -S appuser -u 1001 -G appuser

# Imposta directory di lavoro
WORKDIR /app

# Copia i file dallo stage di build
COPY --from=builder /app /app

# Crea directory per file temporanei
RUN mkdir -p /tmp/icv-uploads \
    && chown -R appuser:appuser /tmp/icv-uploads

# Imposta permessi corretti
RUN chown -R appuser:appuser /app \
    && chmod -R 755 /app \
    && chmod +x server.js

# Cambia a utente non-root
USER appuser

# Esponi la porta (Koyeb usa 8080 di default)
EXPOSE 8080

# Variabili d'ambiente ottimizzate per 512MB RAM
ENV NODE_ENV=production \
    PORT=8080 \
    NODE_OPTIONS="--max-old-space-size=256 --enable-source-maps" \
    UV_THREADPOOL_SIZE=2 \
    TEMP_DIR="/tmp/icv-uploads" \
    MAX_UPLOAD_SIZE="50mb" \
    LOG_LEVEL="info"

# Health check per monitoraggio Koyeb
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

# Usa tini come init per gestire segnali e processi zombie
ENTRYPOINT ["/sbin/tini", "--"]

# Comando di avvio ottimizzato
CMD ["node", "--optimize-for-size", "--trace-warnings", "server.js"]
