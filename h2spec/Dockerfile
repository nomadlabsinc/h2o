FROM golang:1.23-alpine

RUN apk add --no-cache git

RUN go install github.com/summerwind/h2spec/cmd/h2spec@latest

ENTRYPOINT ["h2spec"]
