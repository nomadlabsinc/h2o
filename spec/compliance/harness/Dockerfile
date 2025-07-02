FROM golang:1.21-bookworm

WORKDIR /app

# Install openssl for certificate generation
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# Generate SSL certificates
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Copy go files
COPY go.mod go.sum main.go ./

# Download dependencies
RUN go mod download

# Build the harness with static linking
RUN CGO_ENABLED=0 go build -ldflags '-s -w' -o harness main.go

EXPOSE 8080

# Run with test ID from environment
CMD ["./harness"]