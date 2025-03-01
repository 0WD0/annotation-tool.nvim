#!/usr/bin/env node

import * as net from 'net';
import { createConnection, ProposedFeatures, StreamMessageReader, StreamMessageWriter } from 'vscode-languageserver/node';

// 环境变量配置
const transport = process.env.TRANSPORT || 'stdio';
const host = process.env.HOST || '127.0.0.1';
const port = parseInt(process.env.PORT || '2087', 10);
const debug = process.env.DEBUG === 'true';

// 根据传输方式启动服务器
if (transport === 'stdio') {
    // 使用标准输入/输出
    // 确保在导入 server.ts 之前设置命令行参数
    if (!process.argv.includes('--stdio')) {
        // 直接添加到 process.argv 的第二个位置，避免与其他参数冲突
        process.argv.splice(2, 0, '--stdio');
    }
    
    // 导入server.ts中的内容
    import('./server');
} else if (transport === 'node-ipc') {
    // 使用Node IPC
    if (!process.argv.includes('--node-ipc')) {
        process.argv.splice(2, 0, '--node-ipc');
    }
    
    // 导入server.ts中的内容
    import('./server');
} else if (transport === 'tcp') {
    // 使用TCP
    console.log(`Starting TCP server on ${host}:${port}`);
    
    // 创建TCP服务器
    const server = net.createServer((socket) => {
        console.log('Client connected');
        
        const reader = new StreamMessageReader(socket);
        const writer = new StreamMessageWriter(socket);
        
        // 创建连接
        const connection = createConnection(ProposedFeatures.all, reader, writer);
        
        // 导出连接供server.ts使用
        global.tcpConnection = connection;
        
        socket.on('close', () => {
            console.log('Client disconnected');
        });
        
        // 导入server.ts
        import('./server');
    });
    
    // 监听端口
    server.listen(port, host, () => {
        console.log(`TCP server listening on ${host}:${port}`);
    });
    
    // 设置环境变量
    process.env.NODE_ENV = 'development';
    process.env.VSCODE_DEBUG_MODE = 'true';
    process.env.VSCODE_PIPE_LOGGING = 'true';
    process.env.VSCODE_VERBOSE_LOGGING = debug ? 'true' : 'false';
} else {
    console.error(`Unsupported transport: ${transport}`);
    process.exit(1);
}
