FROM golang:1.21-alpine

WORKDIR /app

# Install openssl for certificate generation
RUN apk add --no-cache openssl

# Generate SSL certificates
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Copy go files
COPY go.mod go.sum main.go ./

# Download dependencies
RUN go mod download

# Build the harness
RUN go build -o harness main.go

EXPOSE 8080

# Run with test ID from environment
CMD ["./harness"]