#!/usr/bin/env node

import { program } from 'commander';
import * as fs from 'fs';
import * as path from 'path';

// 读取 package.json 版本信息
const packagePath = path.join(__dirname, '..', 'package.json');
const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const version = packageJson.version;

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
