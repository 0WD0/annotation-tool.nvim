import {
    createConnection,
    TextDocuments,
    ProposedFeatures,
    InitializeParams,
    TextDocumentSyncKind,
    InitializeResult,
    TextDocumentChangeEvent,
    TextDocumentIdentifier,
    ExecuteCommandParams,
    RemoteConsole,
    Connection
} from 'vscode-languageserver/node';

import {
    TextDocument
} from 'vscode-languageserver-textdocument';

import { URI } from 'vscode-uri';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs/promises';

import { WorkspaceManager } from './workspace';
import { DatabaseManager } from './database';
import { NoteManager } from './note_manager';
import { Logger } from './logger';
import { findAnnotationRanges, extractTextFromRange } from './utils';
import { Config } from './config';

// 声明全局变量类型
declare global {
    var tcpConnection: Connection;
}

// 创建连接
let connection: Connection;
try {
    // 检查是否有TCP连接
    if (global.tcpConnection) {
        global.console.log('Using TCP connection');
        connection = global.tcpConnection;
    } else {
        // 尝试使用命令行参数创建连接
        connection = createConnection(ProposedFeatures.all);
    }
} catch (error) {
    // 如果命令行参数不可用，使用stdio
    global.console.log('Failed to create connection, falling back to stdio');
    connection = createConnection(ProposedFeatures.all);
}

// 获取控制台
const console = connection.console;

// 创建文档管理器
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

// 创建日志记录器
const logger = new Logger(console);

// 创建工作区管理器
const workspaceManager = new WorkspaceManager();

// 数据库和笔记管理器，将在初始化时创建
let dbManager: DatabaseManager | null = null;
let noteManager: NoteManager | null = null;

// 配置
const config = new Config();

/**
 * 初始化服务器
 */
connection.onInitialize((params: InitializeParams): InitializeResult => {
    logger.info('Server initializing...');

    // 处理工作区文件夹
    if (params.workspaceFolders && params.workspaceFolders.length > 0) {
        for (const folder of params.workspaceFolders) {
            const folderUri = folder.uri;
            const folderPath = URI.parse(folderUri).fsPath;
            workspaceManager.addWorkspace(folderUri, folderPath);
            logger.info(`Added workspace: ${folderPath}`);
        }

        // 初始化第一个工作区的数据库和笔记管理器
        const firstWorkspace = workspaceManager.getAllWorkspaces()[0];
        if (firstWorkspace) {
            dbManager = new DatabaseManager(firstWorkspace.rootPath);
            noteManager = new NoteManager(firstWorkspace.rootPath);
            
            // 初始化笔记目录
            noteManager.init().catch(err => {
                logger.error(`Failed to initialize note manager: ${err.message}`);
            });
        }
    }

    return {
        capabilities: {
            textDocumentSync: TextDocumentSyncKind.Incremental,
            // 告诉客户端服务器支持代码完成
            completionProvider: {
                resolveProvider: true
            },
            executeCommandProvider: {
                commands: [
                    'annotation.createNote',
                    'annotation.openNote',
                    'annotation.deleteNote'
                ]
            }
        }
    };
});

/**
 * 连接初始化完成
 */
connection.onInitialized(() => {
    logger.info('Server initialized');
});

/**
 * 文档打开时
 */
documents.onDidOpen((event: TextDocumentChangeEvent<TextDocument>) => {
    const document = event.document;
    const uri = document.uri;
    
    logger.info(`Document opened: ${uri}`);
    
    // 检查文档中的标注
    processAnnotations(document);
});

/**
 * 文档内容变更时
 */
documents.onDidChangeContent((event: TextDocumentChangeEvent<TextDocument>) => {
    const document = event.document;
    const uri = document.uri;
    
    logger.info(`Document changed: ${uri}`);
    
    // 检查文档中的标注
    processAnnotations(document);
});

/**
 * 文档关闭时
 */
documents.onDidClose((event: TextDocumentChangeEvent<TextDocument>) => {
    const document = event.document;
    const uri = document.uri;
    
    logger.info(`Document closed: ${uri}`);
});

/**
 * 处理文档中的标注
 */
async function processAnnotations(document: TextDocument): Promise<void> {
    try {
        const uri = document.uri;
        
        const text = document.getText();
        const ranges = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        
        logger.info(`Found ${ranges.length} annotations in ${uri}`);
        
        // 处理每个标注
        for (const range of ranges) {
            const annotationId = range.id;
            const annotationText = extractTextFromRange(text, range);
            
            // 检查标注是否已存在
            if (dbManager) {
                const exists = await dbManager.annotationExists(uri, annotationId);
                
                if (!exists && noteManager) {
                    // 创建新笔记
                    const noteFile = await noteManager.createAnnotationNote(annotationId);
                    
                    // 保存标注信息
                    await dbManager.saveAnnotation(uri, annotationId, range, noteFile);
                    
                    logger.info(`Created annotation ${annotationId} in ${uri}`);
                }
            }
        }
    } catch (err) {
        logger.error(`Error processing annotations: ${err}`);
    }
}

/**
 * 执行命令
 */
connection.onExecuteCommand(async (params: ExecuteCommandParams) => {
    const command = params.command;
    const args = params.arguments || [];
    
    logger.info(`Executing command: ${command}`);
    
    try {
        switch (command) {
            case 'annotation.createNote':
                return await handleCreateNote(args[0], args[1]);
            
            case 'annotation.openNote':
                return await handleOpenNote(args[0], args[1]);
            
            case 'annotation.deleteNote':
                return await handleDeleteNote(args[0], args[1]);
            
            default:
                logger.error(`Unknown command: ${command}`);
                return null;
        }
    } catch (err) {
        logger.error(`Error executing command ${command}: ${err}`);
        return null;
    }
});

/**
 * 处理创建笔记命令
 */
async function handleCreateNote(uri: string, annotationId: number): Promise<string | null> {
    try {
        logger.info(`Creating note for annotation ${annotationId} in ${uri}`);
        
        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }
        
        // 检查标注是否存在
        const exists = await dbManager.annotationExists(uri, annotationId);
        logger.info(`Annotation exists: ${exists}`);
        
        if (exists) {
            // 获取现有笔记文件
            const noteFile = await dbManager.getAnnotationNoteFile(uri, annotationId);
            
            if (noteFile) {
                logger.info(`Found existing note file: ${noteFile}`);
                return noteFile;
            }
        }
        
        // 获取文档文本
        const document = documents.get(uri);
        if (!document) {
            throw new Error(`Document not found: ${uri}`);
        }
        
        const text = document.getText();
        const ranges = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        logger.info(`Found ${ranges.length} annotations in document`);
        
        // 查找对应的标注
        const range = ranges.find(r => r.id === annotationId);
        if (!range) {
            throw new Error(`Annotation ${annotationId} not found in ${uri}`);
        }
        
        // 提取标注文本
        const annotationText = extractTextFromRange(text, range);
        logger.info(`Extracted annotation text: ${annotationText.substring(0, 50)}${annotationText.length > 50 ? '...' : ''}`);
        
        // 创建笔记文件
        const initialContent = `# Annotation ${annotationId}\n\n${annotationText}\n\n## Notes\n\n`;
        logger.info(`Creating note with initial content length: ${initialContent.length}`);
        
        const noteFile = await noteManager.createAnnotationNote(annotationId, initialContent);
        
        // 保存标注信息
        await dbManager.saveAnnotation(uri, annotationId, range, noteFile);
        
        logger.info(`Created note for annotation ${annotationId} in ${uri}: ${noteFile}`);
        
        return noteFile;
    } catch (err) {
        logger.error(`Error creating note: ${err}`);
        return null;
    }
}

/**
 * 处理打开笔记命令
 */
async function handleOpenNote(uri: string, annotationId: number): Promise<string | null> {
    try {
        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }
        
        // 获取笔记文件
        const noteFile = await dbManager.getAnnotationNoteFile(uri, annotationId);
        
        if (!noteFile) {
            // 如果笔记不存在，创建一个新的
            return await handleCreateNote(uri, annotationId);
        }
        
        // 获取笔记内容
        const content = await noteManager.getNoteContent(noteFile);
        
        return content;
    } catch (err) {
        logger.error(`Error opening note: ${err}`);
        return null;
    }
}

/**
 * 处理删除笔记命令
 */
async function handleDeleteNote(uri: string, annotationId: number): Promise<boolean> {
    try {
        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }
        
        // 获取笔记文件
        const noteFile = await dbManager.getAnnotationNoteFile(uri, annotationId);
        
        if (!noteFile) {
            // 笔记不存在
            return false;
        }
        
        // 删除笔记文件
        await noteManager.deleteAnnotationNote(noteFile);
        
        // 从数据库中删除标注
        await dbManager.deleteAnnotation(uri, annotationId);
        
        logger.info(`Deleted note for annotation ${annotationId} in ${uri}`);
        
        return true;
    } catch (err) {
        logger.error(`Error deleting note: ${err}`);
        return false;
    }
}

// 监听文档管理器
documents.listen(connection);

// 监听连接
connection.listen();
