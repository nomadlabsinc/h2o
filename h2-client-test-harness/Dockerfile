# Use an official Go runtime as a parent image
FROM golang:1.24-alpine

# Set the working directory inside the container
WORKDIR /app

# Install openssl which is required for generating self-signed certificates
RUN apk add --no-cache openssl

# Copy the Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the test runner script first
COPY test-runner.sh /test-runner.sh
RUN chmod +x /test-runner.sh

# Copy the local package source code to the container
COPY . .

# Build both the harness and verifier
RUN go build -o /h2-client-test-harness main.go
RUN go build -o /h2-verifier cmd/verifier/main.go

# Expose port 8080 to the outside world
EXPOSE 8080

# The command to run when the container starts.
ENTRYPOINT ["/test-runner.sh"]
CMD ["--help"]
