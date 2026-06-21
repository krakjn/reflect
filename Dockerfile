FROM alpine:latest

WORKDIR /app

COPY . .

RUN apk add --no-cache \
    musl-dev \
    zig \
    && rm -rf /var/cache/apk/*

RUN zig build

CMD ["zig", "build", "run"]