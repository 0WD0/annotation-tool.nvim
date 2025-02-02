import { program } from 'commander';
import { startServer } from './server';
import { version } from '../package.json';

program
    .version(version)
    .option('--connection <type>', 'Connection type (stdio or tcp)', 'stdio')
    .option('--host <host>', 'Host for TCP connection', '127.0.0.1')
    .option('--port <port>', 'Port for TCP connection', '2087')
    .parse(process.argv);

const options = program.opts();

// 设置环境变量
process.env.CONNECTION_TYPE = options.connection;
if (options.connection === 'tcp') {
    process.env.HOST = options.host;
    process.env.PORT = options.port;
}

// 启动服务器
startServer();
