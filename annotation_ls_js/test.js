#!/usr/bin/env node

// Simple test script to verify the server can start
const { spawn } = require('child_process');
const path = require('path');

console.log('Starting annotation language server test...');

// Path to the compiled server
const serverPath = path.join(__dirname, 'out', 'index.js');

// Start the server process
const serverProcess = spawn('node', [serverPath], {
  env: {
    ...process.env,
    TRANSPORT: 'stdio',
    DEBUG: 'true'
  }
});

// Log server output
serverProcess.stdout.on('data', (data) => {
  console.log(`Server stdout: ${data}`);
});

serverProcess.stderr.on('data', (data) => {
  console.error(`Server stderr: ${data}`);
});

// Exit after 3 seconds
setTimeout(() => {
  console.log('Test completed. Shutting down server...');
  serverProcess.kill();
  process.exit(0);
}, 3000);
