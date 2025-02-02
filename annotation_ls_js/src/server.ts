import {
    createConnection,
    TextDocuments,
    ProposedFeatures,
    InitializeParams,
    TextDocumentSyncKind,
    InitializeResult,
    CodeLens,
    CodeLensParams,
    Command,
    TextDocumentPositionParams,
    Location,
    Range,
    Position,
    TextDocumentIdentifier,
    IPCMessageReader,
    IPCMessageWriter,
    createServerSocketTransport,
    DidChangeConfigurationNotification,
    ExecuteCommandParams
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { DatabaseManager } from './database';
import { NoteManager } from './note';
import * as path from 'path';
import * as fs from 'fs/promises';
import { createServer } from 'net';

// 根据环境变量选择连接类型
let connection: any;
const connectionType = process.env.CONNECTION_TYPE;
const host = process.env.HOST || '127.0.0.1';
const port = parseInt(process.env.PORT || '2087', 10);

if (connectionType === 'tcp') {
    const { createConnection, ProposedFeatures } = require('vscode-languageserver/node');
    const net = require('net');
    
    const server = net.createServer((socket: any) => {
        connection = createConnection(ProposedFeatures.all, socket, socket);
        initializeConnection(connection);
    });
    
    server.listen(port, host);
} else {
    const { createConnection, ProposedFeatures } = require('vscode-languageserver/node');
    connection = createConnection(ProposedFeatures.all);
    initializeConnection(connection);
}

const documents = new TextDocuments(TextDocument);

let dbManager: DatabaseManager;
let noteManager: NoteManager;
let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;

function initializeConnection(connection: any) {
    connection.onInitialize((params: InitializeParams) => {
        const capabilities = params.capabilities;

        hasConfigurationCapability = !!(
            capabilities.workspace && !!capabilities.workspace.configuration
        );
        hasWorkspaceFolderCapability = !!(
            capabilities.workspace && !!capabilities.workspace.workspaceFolders
        );

        const workspaceRoot = params.rootUri ? params.rootUri.replace('file://', '') : null;
        if (workspaceRoot) {
            dbManager = new DatabaseManager(workspaceRoot);
            noteManager = new NoteManager(workspaceRoot);
        }

        const result: InitializeResult = {
            capabilities: {
                textDocumentSync: TextDocumentSyncKind.Incremental,
                codeLensProvider: {
                    resolveProvider: true
                },
                definitionProvider: true,
                executeCommandProvider: {
                    commands: [
                        'annotation.createNote',
                        'annotation.deleteNote',
                        'annotation.gotoSource',
                        'annotation.searchNotes'
                    ]
                }
            }
        };

        return result;
    });

    connection.onInitialized(() => {
        if (hasConfigurationCapability) {
            connection.client.register(
                DidChangeConfigurationNotification.type,
                undefined
            );
        }
        if (hasWorkspaceFolderCapability) {
            connection.workspace.onDidChangeWorkspaceFolders((_event: any) => {
                connection.console.log('Workspace folder change event received.');
            });
        }
    });

    // 实现 CodeLens 提供者
    connection.onCodeLens(async (params: CodeLensParams): Promise<CodeLens[]> => {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            return [];
        }

        const codeLenses: CodeLens[] = [];
        const text = document.getText();
        const lines = text.split('\n');

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const match = line.match(/^(\s*)(.*?)\s*$/);
            if (!match) continue;

            const range = Range.create(i, match[1].length, i, match[0].length);
            codeLenses.push({
                range,
                command: Command.create(
                    'Add Annotation',
                    'annotation.createNote',
                    document.uri,
                    range
                )
            });
        }

        // 获取已有的标注
        const noteFiles = await dbManager.getNoteFilesFromSourceUri(params.textDocument.uri);
        for (const noteFile of noteFiles) {
            const notePath = path.join(dbManager.projectRoot!, '.annotation', 'notes', noteFile);
            const annotationId = await noteManager.getAnnotationIdFromNoteUri(`file://${notePath}`);
            if (annotationId === null) continue;

            // TODO: 从笔记内容中获取原始行号
            const range = Range.create(0, 0, 0, 0);
            codeLenses.push({
                range,
                command: Command.create(
                    `View Annotation #${annotationId}`,
                    'annotation.gotoNote',
                    document.uri,
                    annotationId
                )
            });
        }

        return codeLenses;
    });

    // 实现定义跳转
    connection.onDefinition(async (params: TextDocumentPositionParams): Promise<Location | null> => {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            return null;
        }

        // 检查当前文件是否是笔记文件
        if (!params.textDocument.uri.includes('.annotation/notes/')) {
            return null;
        }

        // 获取源文件路径
        const sourcePath = await noteManager.getSourcePathFromNoteUri(params.textDocument.uri);
        if (!sourcePath) {
            return null;
        }

        // 返回源文件位置
        return Location.create(
            `file://${sourcePath}`,
            Range.create(Position.create(0, 0), Position.create(0, 0))
        );
    });

    // 实现命令处理
    connection.onExecuteCommand(async (params: ExecuteCommandParams) => {
        switch (params.command) {
            case 'annotation.createNote': {
                const [uri, range] = params.arguments || [];
                if (!uri || !range) {
                    return null;
                }

                const document = documents.get(uri);
                if (!document) {
                    return null;
                }

                // 创建新的标注
                const annotationId = 1; // TODO: 生成新的标注 ID
                await dbManager.createAnnotation(uri, annotationId);

                // 创建笔记文件
                const noteDir = path.join(dbManager.projectRoot!, '.annotation', 'notes');
                await fs.mkdir(noteDir, { recursive: true });

                const noteFile = `note_${Date.now()}.md`;
                const notePath = path.join(noteDir, noteFile);

                const selectedText = document.getText(range);
                const noteContent = `---
file: ${path.relative(dbManager.projectRoot!, document.uri)}
id: ${annotationId}
---

${selectedText}

`;
                await fs.writeFile(notePath, noteContent);

                return;
            }

            case 'annotation.deleteNote': {
                const [uri, annotationId] = params.arguments || [];
                if (!uri || annotationId === undefined) {
                    return null;
                }

                await dbManager.deleteAnnotation(uri, annotationId);
                return;
            }

            case 'annotation.gotoSource': {
                const [noteUri] = params.arguments || [];
                if (!noteUri) {
                    return null;
                }

                const sourcePath = await noteManager.getSourcePathFromNoteUri(noteUri);
                if (!sourcePath) {
                    return null;
                }

                // 返回源文件位置
                return Location.create(
                    `file://${sourcePath}`,
                    Range.create(Position.create(0, 0), Position.create(0, 0))
                );
            }

            case 'annotation.searchNotes': {
                const [query, searchType] = params.arguments || [];
                if (!query) {
                    return [];
                }

                return await noteManager.searchNotes(query, searchType || 'all');
            }
        }
    });

    // 监听文档变化
    documents.onDidChangeContent(change => {
        validateTextDocument(change.document);
    });

    async function validateTextDocument(textDocument: TextDocument): Promise<void> {
        // 实现文档验证逻辑
    }

    // 监听打开的文档
    documents.listen(connection);

    connection.listen();
}

export function startServer() {
    connection.listen();
}
