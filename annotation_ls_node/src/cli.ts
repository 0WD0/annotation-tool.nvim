#!/usr/bin/env node

import { program } from 'commander';
import { version } from '../package.json';

program
    .version(version)
    .option('-t, --transport <type>', 'Transport type (stdio or tcp)', 'stdio')
    .option('-h, --host <host>', 'Host for TCP connection', '127.0.0.1')
    .option('-p, --port <port>', 'Port for TCP connection', '2087')
    .option('-d, --debug', 'Enable debug mode')
    .parse(process.argv);

const options = program.opts();

// 设置环境变量
process.env.TRANSPORT = options.transport;
process.env.HOST = options.host;
process.env.PORT = options.port;
process.env.DEBUG = options.debug ? 'true' : 'false';

// 启动服务器
require('./index');
