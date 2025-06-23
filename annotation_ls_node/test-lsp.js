#!/usr/bin/env node

// A more comprehensive test script that sends actual LSP messages to the server
const { spawn } = require('child_process');
const path = require('path');
const net = require('net');
const fs = require('fs');

console.log('Starting LSP test...');

// Path to the compiled server
const serverPath = path.join(__dirname, 'out', 'index.js');

// Start the server process with TCP transport
const port = 8999;
const serverProcess = spawn('node', [serverPath], {
  env: {
    ...process.env,
    TRANSPORT: 'tcp',
    PORT: port.toString(),
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

// Wait a bit for the server to start
setTimeout(() => {
  // Connect to the server
  const client = new net.Socket();
  
  client.connect(port, '127.0.0.1', () => {
    console.log('Connected to LSP server');
    
    // Send initialize request
    const initializeRequest = {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        processId: process.pid,
        rootPath: __dirname,
        capabilities: {},
        workspaceFolders: [
          {
            uri: `file://${__dirname}`,
            name: 'test-workspace'
          }
        ]
      }
    };
    
    client.write(
      `Content-Length: ${Buffer.byteLength(JSON.stringify(initializeRequest), 'utf8')}\r\n\r\n${JSON.stringify(initializeRequest)}`
    );
    
    // After 1 second, send initialized notification
    setTimeout(() => {
      const initializedNotification = {
        jsonrpc: '2.0',
        method: 'initialized',
        params: {}
      };
      
      client.write(
        `Content-Length: ${Buffer.byteLength(JSON.stringify(initializedNotification), 'utf8')}\r\n\r\n${JSON.stringify(initializedNotification)}`
      );
      
      console.log('Sent initialized notification');
      
      // After another 1 second, open the test file
      setTimeout(() => {
        // Read the test file
        const testFilePath = path.join(__dirname, 'test-file.txt');
        const fileContent = fs.readFileSync(testFilePath, 'utf8');
        
        // Send didOpen notification
        const didOpenNotification = {
          jsonrpc: '2.0',
          method: 'textDocument/didOpen',
          params: {
            textDocument: {
              uri: `file://${testFilePath}`,
              languageId: 'plaintext',
              version: 1,
              text: fileContent
            }
          }
        };
        
        client.write(
          `Content-Length: ${Buffer.byteLength(JSON.stringify(didOpenNotification), 'utf8')}\r\n\r\n${JSON.stringify(didOpenNotification)}`
        );
        
        console.log('Sent didOpen notification for test file');
        
        // After another 2 seconds, close the connection and exit
        setTimeout(() => {
          console.log('Test completed successfully');
          client.end();
          serverProcess.kill();
          process.exit(0);
        }, 2000);
      }, 1000);
    }, 1000);
  });
  
  // Handle data from the server
  client.on('data', (data) => {
    console.log('Received from server:', data.toString());
  });
  
  // Handle connection errors
  client.on('error', (err) => {
    console.error('Connection error:', err);
    serverProcess.kill();
    process.exit(1);
  });
}, 1000);
