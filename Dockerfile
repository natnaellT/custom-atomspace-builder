FROM maven:3.8-openjdk-17 AS hugegraph-builder

WORKDIR /build

COPY pom.xml .
COPY hugegraph-loader/pom.xml hugegraph-loader/
COPY hugegraph-client/pom.xml hugegraph-client/
COPY hugegraph-loader-custom/pom.xml hugegraph-loader-custom/
RUN mvn dependency:go-offline -pl hugegraph-client,hugegraph-loader -am

COPY . .
RUN if [ -f build-artifacts/loader-dist.tar.gz ]; then \
        echo "Using pre-built loader from build-artifacts/"; \
        mkdir -p loader-output && tar xzf build-artifacts/loader-dist.tar.gz -C loader-output; \
    else \
        echo "Building HugeGraph Loader from source..."; \
        mvn clean install -pl hugegraph-client,hugegraph-loader \
            -Dmaven.javadoc.skip=true -DskipTests -Dcheckstyle.skip=true -Deditorconfig.skip=true && \
        mvn install -pl hugegraph-loader-custom \
            -Dmaven.javadoc.skip=true -DskipTests -Dcheckstyle.skip=true -Deditorconfig.skip=true && \
        mvn package -pl hugegraph-loader -Pwith-custom \
            -Dmaven.javadoc.skip=true -DskipTests -Dcheckstyle.skip=true -Deditorconfig.skip=true && \
        mkdir -p loader-output && cp -r hugegraph-loader/apache-hugegraph-loader-incubating-1.5.0/. loader-output/; \
    fi

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    HUGEGRAPH_LOADER_PATH=/app/hugegraph-loader/bin/hugegraph-loader.sh

ARG API_PORT=8000
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    default-jre-headless \
    bash \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=hugegraph-builder /build/loader-output /app/hugegraph-loader

COPY app/ ./app/
COPY config.yaml .

RUN mkdir -p output uploads logs \
    && chmod +x /app/hugegraph-loader/bin/hugegraph-loader.sh

RUN echo "Verifying HugeGraph Loader installation..." && \
    ls -la /app/hugegraph-loader/bin/ && \
    echo "HugeGraph Loader path: $HUGEGRAPH_LOADER_PATH" && \
    test -f "$HUGEGRAPH_LOADER_PATH" && \
    echo "HugeGraph Loader verification successful"

EXPOSE ${API_PORT}
CMD ["python", "-m", "app.main"]
