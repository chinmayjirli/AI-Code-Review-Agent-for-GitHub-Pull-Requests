# syntax=docker/dockerfile:1
FROM eclipse-temurin:21-jre-alpine

# Non-root user for security
RUN addgroup -S reviewer && adduser -S reviewer -G reviewer

WORKDIR /app

# Copy the fat-jar built by Spring Boot Maven plugin
COPY target/ai-code-reviewer-*.jar app.jar

USER reviewer

EXPOSE 8080

# Secrets MUST be injected as environment variables at runtime:
#   docker run -e GITHUB_APP_WEBHOOK_SECRET=... \
#              -e GITHUB_APP_ID=... \
#              -e GITHUB_APP_PRIVATE_KEY_PATH=/run/secrets/github_pk \
#              ...
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
