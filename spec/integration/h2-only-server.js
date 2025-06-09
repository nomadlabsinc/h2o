#!/usr/bin/env node

const http2 = require('http2');
const fs = require('fs');
const path = require('path');

// Read SSL certificates
const sslPath = path.join(__dirname, 'ssl');
const options = {
  key: fs.readFileSync(path.join(sslPath, 'key.pem')),
  cert: fs.readFileSync(path.join(sslPath, 'cert.pem')),
  // Force HTTP/2 only - reject HTTP/1.1 connections
  allowHTTP1: false,
  settings: {
    // HTTP/2 specific settings
    headerTableSize: 4096,
    enablePush: false,
    maxConcurrentStreams: 100,
    initialWindowSize: 65535,
    maxFrameSize: 16384,
    maxHeaderListSize: 8192
  }
};

// Create HTTP/2 server that explicitly rejects HTTP/1.1
const server = http2.createSecureServer(options);

server.on('error', (err) => {
  console.error('Server error:', err);
});

server.on('request', (req, res) => {
  const url = new URL(req.url, `https://${req.headers.host}`);
  console.log(`${req.method} ${url.pathname} - HTTP/${req.httpVersion}`);

  // Ensure we're really using HTTP/2
  if (req.httpVersion !== '2.0') {
    res.writeHead(426, {
      'content-type': 'application/json',
      'upgrade': 'HTTP/2'
    });
    res.end(JSON.stringify({
      error: 'HTTP/2 Required',
      message: 'This server only accepts HTTP/2 connections',
      protocol_received: `HTTP/${req.httpVersion}`,
      required_protocol: 'HTTP/2.0'
    }));
    return;
  }

  // Set common headers
  res.setHeader('content-type', 'application/json');
  res.setHeader('server', 'h2o-test-http2-only');

  // Route handling
  switch (url.pathname) {
    case '/health':
      res.writeHead(200);
      res.end(JSON.stringify({
        status: 'healthy',
        protocol: `HTTP/${req.httpVersion}`,
        http2_only: true,
        server: 'Node.js HTTP/2 Only'
      }));
      break;

    case '/headers':
      res.writeHead(200);
      res.end(JSON.stringify({
        headers: Object.fromEntries(Object.entries(req.headers)),
        protocol: `HTTP/${req.httpVersion}`,
        method: req.method,
        url: req.url
      }));
      break;

    case '/status/200':
      res.writeHead(200);
      res.end(JSON.stringify({
        status: 200,
        protocol: `HTTP/${req.httpVersion}`
      }));
      break;

    case '/reject-h1':
      res.writeHead(200);
      res.end(JSON.stringify({
        message: 'This endpoint only works with HTTP/2',
        protocol: `HTTP/${req.httpVersion}`,
        connection_successful: true
      }));
      break;

    default:
      res.writeHead(200);
      res.end(JSON.stringify({
        message: 'HTTP/2 only server',
        protocol: `HTTP/${req.httpVersion}`,
        method: req.method,
        path: url.pathname,
        timestamp: new Date().toISOString()
      }));
  }
});

// Handle HTTP/1.1 connection attempts
server.on('clientError', (err, socket) => {
  console.log('Client error (likely HTTP/1.1 attempt):', err.message);

  if (err.code === 'EPROTO' || err.message.includes('HTTP/1.1')) {
    // Send HTTP/1.1 response indicating HTTP/2 requirement
    const response = [
      'HTTP/1.1 426 Upgrade Required',
      'Content-Type: application/json',
      'Upgrade: h2',
      'Connection: Upgrade',
      'Content-Length: 140',
      '',
      '{"error":"HTTP/2 Required","message":"This server only accepts HTTP/2 connections","required_protocol":"HTTP/2.0","upgrade_to":"h2"}'
    ].join('\r\n');

    socket.write(response);
    socket.end();
  } else {
    socket.destroy();
  }
});

const PORT = process.env.PORT || 8447;

server.listen(PORT, () => {
  console.log(`HTTP/2-only server listening on port ${PORT}`);
  console.log('This server will reject HTTP/1.1 connections');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down HTTP/2-only server...');
  server.close(() => {
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('Shutting down HTTP/2-only server...');
  server.close(() => {
    process.exit(0);
  });
});
