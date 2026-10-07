FROM golang:1-alpine AS build
RUN go install tailscale.com/cmd/derper@latest

FROM alpine:3
RUN apk add --no-cache ca-certificates
COPY --from=build /go/bin/derper /usr/local/bin/derper
ENTRYPOINT ["derper"]
