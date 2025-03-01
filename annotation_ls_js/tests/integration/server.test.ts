import * as path from 'path';
import * as net from 'net';
import * as fs from 'fs/promises';
import { spawn, ChildProcess } from 'child_process';

// 创建临时测试目录
const TEST_DIR = path.join(__dirname, '../../.test-temp');
const TEST_FILE = path.join(TEST_DIR, 'test-file.txt');
const SERVER_PORT = 9876;

// 增加测试超时时间
jest.setTimeout(30000);

describe('LSP Server Integration Tests', () => {
  let serverProcess: ChildProcess;
  let client: net.Socket;
  let messageBuffer = '';
  
  // 在所有测试开始前设置测试环境
  beforeAll(async () => {
    // 创建测试目录和文件
    await fs.mkdir(TEST_DIR, { recursive: true });
    await fs.writeFile(TEST_FILE, `This is a test file with annotations.

「1」This is the first annotation「1」

Some text in between annotations.

「2」This is the second annotation「2」

End of file.
`);
    
    // 启动服务器进程
    serverProcess = spawn('node', [
      path.join(__dirname, '../../out/cli.js'),
      '--transport=tcp',
      `--port=${SERVER_PORT}`
    ], {
      env: {
        ...process.env,
        DEBUG: 'true'
      }
    });
    
    // 输出服务器日志以便调试
    if (serverProcess.stdout) {
      serverProcess.stdout.on('data', (data) => {
        console.log(`Server stdout: ${data}`);
      });
    }
    
    if (serverProcess.stderr) {
      serverProcess.stderr.on('data', (data) => {
        console.error(`Server stderr: ${data}`);
      });
    }
    
    // 等待服务器启动
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // 连接到服务器
    client = new net.Socket();
    await new Promise<void>((resolve, reject) => {
      client.connect(SERVER_PORT, '127.0.0.1', () => {
        console.log('Connected to server');
        resolve();
      });
      client.on('error', (err) => {
        console.error('Connection error:', err);
        reject(err);
      });
    });
  });
  
  // 在所有测试结束后清理测试环境
  afterAll(async () => {
    // 关闭客户端连接
    if (client) {
      client.destroy();
    }
    
    // 终止服务器进程
    if (serverProcess) {
      serverProcess.kill();
    }
    
    // 删除测试目录
    try {
      await fs.rm(TEST_DIR, { recursive: true, force: true });
    } catch (err) {
      console.error('Failed to clean up test directory:', err);
    }
  });
  
  // 发送LSP请求并等待响应
  const sendRequest = async (method: string, params: any): Promise<any> => {
    return new Promise((resolve, reject) => {
      const id = Math.floor(Math.random() * 1000000);
      const request = {
        jsonrpc: '2.0',
        id,
        method,
        params
      };
      
      const requestStr = JSON.stringify(request);
      const contentLength = Buffer.byteLength(requestStr, 'utf8');
      const header = `Content-Length: ${contentLength}\r\n\r\n`;
      
      console.log(`Sending request: ${method}`);
      client.write(header + requestStr);
      
      let responseData = '';
      
      const onData = (data: Buffer) => {
        const dataStr = data.toString();
        responseData += dataStr;
        
        // 解析响应
        try {
          // 查找响应头和正文的分隔符
          const headerEnd = responseData.indexOf('\r\n\r\n');
          if (headerEnd === -1) return; // 头部不完整，等待更多数据
          
          // 解析头部
          const headerStr = responseData.substring(0, headerEnd);
          const contentLengthMatch = headerStr.match(/Content-Length: (\d+)/i);
          if (!contentLengthMatch) return; // 没有Content-Length头
          
          const contentLength = parseInt(contentLengthMatch[1], 10);
          const bodyStart = headerEnd + 4; // 跳过'\r\n\r\n'
          
          // 检查是否收到了完整的消息体
          if (responseData.length < bodyStart + contentLength) return; // 消息体不完整，等待更多数据
          
          const body = responseData.substring(bodyStart, bodyStart + contentLength);
          console.log(`Received response body: ${body}`);
          
          const response = JSON.parse(body);
          
          // 检查是否是我们等待的响应
          if (response.id === id) {
            client.removeListener('data', onData);
            resolve(response);
          }
        } catch (err) {
          console.error('Error parsing response:', err);
          console.error('Response data:', responseData);
          client.removeListener('data', onData);
          reject(err);
        }
      };
      
      client.on('data', onData);
      
      // 设置超时
      setTimeout(() => {
        client.removeListener('data', onData);
        reject(new Error('Request timed out'));
      }, 10000);
    });
  };
  
  // 测试初始化请求
  test('initialize request should return server capabilities', async () => {
    const response = await sendRequest('initialize', {
      processId: process.pid,
      rootPath: TEST_DIR,
      capabilities: {}
    });
    
    expect(response.result).toBeDefined();
    expect(response.result.capabilities).toBeDefined();
    expect(response.result.capabilities.textDocumentSync).toBeDefined();
    expect(response.result.capabilities.executeCommandProvider).toBeDefined();
    expect(response.result.capabilities.executeCommandProvider.commands).toContain('annotation.createNote');
  }, 15000);
  
  // 测试打开文档
  test('didOpen notification should process document annotations', async () => {
    // 发送initialized通知
    const initializedRequest = {
      jsonrpc: '2.0',
      method: 'initialized',
      params: {}
    };
    
    const initializedStr = JSON.stringify(initializedRequest);
    const contentLength = Buffer.byteLength(initializedStr, 'utf8');
    const header = `Content-Length: ${contentLength}\r\n\r\n`;
    
    client.write(header + initializedStr);
    
    // 等待服务器处理
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 发送didOpen通知
    const didOpenRequest = {
      jsonrpc: '2.0',
      method: 'textDocument/didOpen',
      params: {
        textDocument: {
          uri: `file://${TEST_FILE.replace(/\\/g, '/')}`,
          languageId: 'plaintext',
          version: 1,
          text: await fs.readFile(TEST_FILE, 'utf8')
        }
      }
    };
    
    const didOpenStr = JSON.stringify(didOpenRequest);
    const didOpenContentLength = Buffer.byteLength(didOpenStr, 'utf8');
    const didOpenHeader = `Content-Length: ${didOpenContentLength}\r\n\r\n`;
    
    client.write(didOpenHeader + didOpenStr);
    
    // 等待服务器处理
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // 测试执行命令
    const response = await sendRequest('workspace/executeCommand', {
      command: 'annotation.createNote',
      arguments: [
        `file://${TEST_FILE.replace(/\\/g, '/')}`,
        1
      ]
    });
    
    expect(response.result).toBeDefined();
    expect(typeof response.result).toBe('string');
    expect(response.result).toContain('annotation_1.md');
    
    // 检查笔记文件是否已创建
    const notesDir = path.join(TEST_DIR, '.annotations', 'notes');
    const noteFiles = await fs.readdir(notesDir);
    
    expect(noteFiles).toContain('annotation_1.md');
    
    // 检查笔记内容
    const noteContent = await fs.readFile(path.join(notesDir, 'annotation_1.md'), 'utf8');
    expect(noteContent).toContain('Annotation 1');
    expect(noteContent).toContain('This is the first annotation');
  }, 20000);
});
