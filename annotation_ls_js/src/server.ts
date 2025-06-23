import {
    createConnection,
    TextDocuments,
    ProposedFeatures,
    InitializeParams,
    TextDocumentSyncKind,
    InitializeResult,
    TextDocumentChangeEvent,
    ExecuteCommandParams,
    Connection,
    DocumentHighlightParams,
    HoverParams,
    CompletionItemKind,
    CompletionParams,
    CompletionList,
} from 'vscode-languageserver/node';

import {
    TextDocument
} from 'vscode-languageserver-textdocument';

import { URI } from 'vscode-uri';

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
        // 检查命令行参数是否包含必要的通信参数
        const hasStdio = process.argv.includes('--stdio');
        const hasNodeIpc = process.argv.includes('--node-ipc');
        const hasSocket = process.argv.some(arg => arg.startsWith('--socket='));
        
        if (!hasStdio && !hasNodeIpc && !hasSocket) {
            global.console.log('No connection method specified, defaulting to stdio');
            process.argv.push('--stdio');
        }
        
        // 创建连接
        connection = createConnection(ProposedFeatures.all);
    }
} catch (error) {
    // 如果创建连接失败，记录错误并尝试使用stdio
    global.console.error('Failed to create connection:', error);
    if (!process.argv.includes('--stdio')) {
        global.console.log('Falling back to stdio');
        process.argv.push('--stdio');
    }
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

    // 返回服务器能力
    return {
        capabilities: {
            textDocumentSync: TextDocumentSyncKind.Incremental,
            // 告诉客户端服务器支持代码完成
            completionProvider: {
                resolveProvider: true,
                triggerCharacters: ['@', '#', '$']
            },
            executeCommandProvider: {
                commands: [
                    'createAnnotation',
                    'deleteAnnotation',
                    'deleteAnnotationR',
                    'getAnnotationNote',
                    'getAnnotationSource',
                    'queryAnnotations'
                ]
            },
            hoverProvider: true,
            documentHighlightProvider: true // 添加文档高亮提供者
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
 * 处理悬停请求
 */
connection.onHover(async (params: HoverParams) => {
    try {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            logger.error(`Document not found: ${params.textDocument.uri}`);
            return null;
        }

        // 获取当前位置的标注
        const text = document.getText();
        const position = params.position;

        // 查找所有标注范围
        const annotations = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        if (!annotations || annotations.length === 0) {
            logger.info('No annotations found in document');
            return null;
        }

        // 检查当前位置是否在某个标注范围内
        for (const annotation of annotations) {
            const { start, end } = annotation;
            
            // 检查位置是否在范围内
            if ((start.line < position.line || (start.line === position.line && start.character <= position.character)) &&
                (end.line > position.line || (end.line === position.line && end.character >= position.character))) {
                
                if (!dbManager || !noteManager) {
                    return {
                        contents: `Annotation ${annotation.id}`
                    };
                }

                // 获取笔记文件内容
                try {
                    const noteFile = await dbManager.getAnnotationNoteFile(params.textDocument.uri, annotation.id);
                    if (noteFile) {
                        const noteContent = await noteManager.getNoteContent(noteFile);
                        if (noteContent) {
                            // 只显示 ## Notes 后面的内容
                            const notesContent = noteManager.extractNotesContent(noteContent);
                            if (notesContent) {
                                return {
                                    contents: {
                                        kind: 'markdown',
                                        value: notesContent
                                    }
                                };
                            }
                        }
                    }
                } catch (err) {
                    logger.error(`Error getting note content for hover: ${err}`);
                }
                
                // 如果无法获取笔记内容，返回基本信息
                return {
                    contents: `Annotation ${annotation.id}`
                };
            }
        }

        return null;
    } catch (error) {
        logger.error(`Error in hover: ${error}`);
        return null;
    }
});

/**
 * 处理文档高亮请求
 */
connection.onDocumentHighlight(async (params: DocumentHighlightParams) => {
    try {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            logger.error(`Document not found: ${params.textDocument.uri}`);
            return null;
        }

        // 获取当前位置的标注
        const text = document.getText();
        const position = params.position;

        // 查找所有标注范围
        const annotations = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        if (!annotations || annotations.length === 0) {
            logger.info('No annotations found in document');
            return null;
        }

        // 检查当前位置是否在某个标注范围内
        for (const annotation of annotations) {
            const { start, end } = annotation;
            
            // 检查位置是否在范围内
            if ((start.line < position.line || (start.line === position.line && start.character <= position.character)) &&
                (end.line > position.line || (end.line === position.line && end.character >= position.character))) {
                
                // 返回需要高亮的范围
                return [{
                    range: {
                        start: { line: start.line, character: start.character },
                        end: { line: end.line, character: end.character }
                    }
                }];
            }
        }

        return null;
    } catch (error) {
        logger.error(`Error in document highlight: ${error}`);
        return null;
    }
});

/**
 * 处理代码完成请求
 */
connection.onCompletion(async (params: CompletionParams) => {
    try {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            logger.error(`Document not found: ${params.textDocument.uri}`);
            return null;
        }

        // 获取当前位置的标注
        const text = document.getText();
        const position = params.position;

        // 查找所有标注范围
        const annotations = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        if (!annotations || annotations.length === 0) {
            logger.info('No annotations found in document');
            return null;
        }

        // 检查当前位置是否在某个标注范围内
        for (const annotation of annotations) {
            const { start, end } = annotation;
            
            // 检查位置是否在范围内
            if ((start.line < position.line || (start.line === position.line && start.character <= position.character)) &&
                (end.line > position.line || (end.line === position.line && end.character >= position.character))) {
                
                // 返回代码完成建议
                return {
                    isIncomplete: false,
                    items: [
                        {
                            label: `Annotation ${annotation.id}`,
                            kind: CompletionItemKind.Function,
                            detail: 'Annotation',
                            documentation: 'This is an annotation'
                        }
                    ]
                } as CompletionList;
            }
        }

        return null;
    } catch (error) {
        logger.error(`Error in completion: ${error}`);
        return null;
    }
});

/**
 * 处理创建标注命令
 */
async function handleCreateAnnotation(params: any): Promise<any> {
    try {
        logger.info(`Creating annotation with params: ${JSON.stringify(params)}`);
        
        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }
        
        const uri = params.textDocument.uri;
        const selectionRange = params.range;
        
        // 获取文档文本
        const document = documents.get(uri);
        if (!document) {
            throw new Error(`Document not found: ${uri}`);
        }
        
        const text = document.getText();
        
        // 提取选中的文本
        const selectedText = extractTextFromRange(text, selectionRange);
        logger.info(`Selected text: ${selectedText.substring(0, 50)}${selectedText.length > 50 ? '...' : ''}`);
        
        // 获取选中位置前的标注 ID
        const ranges = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
        let annotationId = 1; // 默认从 1 开始
        
        // 类似于 Python 版本的 get_annotation_id_before_position
        // 找到在选中位置之前的最后一个标注 ID
        for (const range of ranges) {
            if (
                range.start.line < selectionRange.start.line || 
                (range.start.line === selectionRange.start.line && range.start.character < selectionRange.start.character)
            ) {
                annotationId = Math.max(annotationId, range.id + 1);
            }
        }
        
        logger.info(`Using annotation ID: ${annotationId}`);
        
        // 在数据库中更新可能受影响的标注 ID
        await dbManager.increaseAnnotationIds(uri, annotationId);
        
        // 创建带 frontmatter 的笔记文件
        const noteFile = `note_${annotationId}.md`;
        logger.info(`Creating note with frontmatter for annotation ${annotationId}`);
        
        await noteManager.createAnnotationNoteWithFrontmatter(uri, annotationId, selectedText, noteFile);
        
        // 保存标注信息
        await dbManager.saveAnnotation(uri, annotationId, selectionRange, noteFile);
        
        // 在原文中插入括号
        // 这部分在 Python 版本中是通过 LSP 的 apply_edit 实现的
        // 但在 JS 版本中，我们可能需要另外的机制
        // 这里先不实现，因为可能需要客户端配合
        
        return {
            success: true,
            annotationId: annotationId,
            noteFile: noteFile
        };
    } catch (err) {
        logger.error(`Error creating annotation: ${err}`);
        return {
            success: false,
            error: `${err}`
        };
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
            case 'createAnnotation':
                logger.info(`CreateAnnotation args: ${JSON.stringify(args)}`);
                return await handleCreateAnnotation(args[0]);
            
            case 'deleteAnnotation':
                return await handleDeleteNote(args[0].textDocument.uri, args[0].annotationId);
            
            case 'deleteAnnotationR':
                return await handleDeleteAnnotationR(args[0]);
            
            case 'getAnnotationNote':
                return await handleGetAnnotationNote(args[0].textDocument.uri, args[0].annotationId);
            
            case 'getAnnotationSource':
                return await handleGetAnnotationSource(args[0].textDocument.uri, args[0].offset || 0);
            
            case 'queryAnnotations':
                return await handleQueryAnnotations(args[0]);
            
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
 * 处理打开笔记命令
 */
async function handleGetAnnotationNote(uri: string, annotationId: number): Promise<string | null> {
    try {
        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }
        
        // 获取笔记文件
        const noteFile = await dbManager.getAnnotationNoteFile(uri, annotationId);
        
        if (!noteFile) {
            // 如果笔记不存在，创建一个新的
            return await handleCreateAnnotation({ textDocument: { uri }, range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } } });
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
 * 处理获取源代码命令
 */
async function handleGetAnnotationSource(uri: string, annotationId: number): Promise<string | null> {
    try {
        if (!dbManager) {
            throw new Error('Database not initialized');
        }
        
        // 获取标注信息
        const annotations = await dbManager.getAnnotations(uri);
        const annotation = annotations.find(a => a.id === annotationId);
        
        if (!annotation) {
            throw new Error(`Annotation ${annotationId} not found in ${uri}`);
        }
        
        // 获取文档文本
        const document = documents.get(uri);
        if (!document) {
            throw new Error(`Document not found: ${uri}`);
        }
        
        const text = document.getText();
        
        // 提取标注文本
        const annotationText = extractTextFromRange(text, annotation.range);
        
        return annotationText;
    } catch (err) {
        logger.error(`Error getting annotation source: ${err}`);
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

/**
 * 处理从笔记文件反向删除标注命令
 */
async function handleDeleteAnnotationR(params: any): Promise<any> {
    try {
        const noteUri = params.textDocument.uri;
        const noteDocument = documents.get(noteUri);
        
        if (!noteDocument) {
            throw new Error(`Note document not found: ${noteUri}`);
        }

        if (!dbManager || !noteManager) {
            throw new Error('Database or note manager not initialized');
        }

        // 从笔记文件路径获取标注ID和源文件路径
        const parseResult = await noteManager.parseNoteFile(noteUri);
        
        if (!parseResult || !parseResult.annotationId || !parseResult.sourceUri) {
            throw new Error('Failed to parse note file information');
        }
        
        const { annotationId, sourceUri } = parseResult;

        // 检查源文件是否存在
        const fs = require('fs');
        const sourcePath = URI.parse(sourceUri).fsPath;
        
        if (fs.existsSync(sourcePath)) {
            // 源文件存在，执行正常的删除流程
            const sourceDocument = documents.get(sourceUri);
            if (sourceDocument) {
                // 找到标注位置并删除
                const text = sourceDocument.getText();
                const ranges = findAnnotationRanges(text, config.leftBracket, config.rightBracket);
                const targetRange = ranges.find(r => r.id === annotationId);
                
                if (targetRange) {
                    // 删除数据库记录
                    await dbManager.deleteAnnotation(sourceUri, annotationId);
                    
                    // 删除笔记文件
                    const noteFile = await dbManager.getAnnotationNoteFile(sourceUri, annotationId);
                    if (noteFile) {
                        await noteManager.deleteAnnotationNote(noteFile);
                    }
                    
                    logger.info(`Deleted annotation ${annotationId} from ${sourceUri}`);
                    return { success: true, noteFile };
                }
            }
        } else {
            // 源文件不存在，只删除笔记文件和数据库记录
            logger.info(`Source file does not exist: ${sourcePath}, deleting annotation file only`);
            
            const noteFile = await dbManager.getAnnotationNoteFile(sourceUri, annotationId);
            if (noteFile) {
                await dbManager.deleteAnnotation(sourceUri, annotationId);
                await noteManager.deleteAnnotationNote(noteFile);
                
                logger.info(`Successfully deleted orphaned annotation: ${noteFile}`);
                return { success: true, noteFile, orphaned: true };
            }
        }
        
        throw new Error('Failed to delete annotation');
    } catch (err) {
        logger.error(`Failed to delete annotation R: ${err}`);
        return { success: false, error: `${err}` };
    }
}

/**
 * 处理查询标注命令
 */
async function handleQueryAnnotations(params: any): Promise<any[]> {
    try {
        const uri = params.textDocument.uri;
        const scope = params.scope || 'current_file';
        
        if (!dbManager) {
            throw new Error('Database not initialized');
        }
        
        const workspace = workspaceManager.getWorkspace(uri);
        if (!workspace) {
            logger.error(`No workspace found for ${uri}`);
            return [];
        }

        const result: any[] = [];

        switch (scope) {
            case 'current_file':
                // 获取当前文件的所有标注
                const noteFiles = await dbManager.getNoteFilesFromSourceUri(uri);
                return [{
                    workspace_path: workspace.rootPath,
                    note_files: noteFiles.map(file => ({ note_file: file }))
                }];

            case 'current_workspace':
                // 获取当前工作区的所有标注
                return await getWorkspaceAnnotations([workspace]);

            case 'current_project':
                // 获取当前项目（工作区树）的所有标注
                const allWorkspaces = workspaceManager.getAllWorkspaces();
                return await getWorkspaceAnnotations(allWorkspaces);

            default:
                logger.info(`Unknown query scope: ${scope}, defaulting to current_file`);
                const defaultNoteFiles = await dbManager.getNoteFilesFromSourceUri(uri);
                return [{
                    workspace_path: workspace.rootPath,
                    note_files: defaultNoteFiles.map(file => ({ note_file: file }))
                }];
        }
    } catch (err) {
        logger.error(`Error querying annotations: ${err}`);
        return [];
    }
}

/**
 * 获取工作区标注的辅助函数
 */
async function getWorkspaceAnnotations(workspaces: any[]): Promise<any[]> {
    const result: any[] = [];
    
    for (const workspace of workspaces) {
        try {
            // 扫描工作区的 .annotation/notes 目录
            const notesDir = noteManager?.getNotesDir(workspace.rootPath);
            if (!notesDir) continue;

            const fs = require('fs');
            const path = require('path');
            
            if (fs.existsSync(notesDir)) {
                const noteFiles: any[] = [];
                const files = fs.readdirSync(notesDir);
                
                for (const file of files) {
                    if (file.endsWith('.md')) {
                        noteFiles.push({ note_file: file });
                    }
                }
                
                if (noteFiles.length > 0) {
                    result.push({
                        workspace_path: workspace.rootPath,
                        note_files: noteFiles
                    });
                }
            }
        } catch (err) {
            logger.error(`Error scanning workspace ${workspace.rootPath}: ${err}`);
        }
    }
    
    return result;
}

// 监听文档管理器
documents.listen(connection);

// 监听连接
connection.listen();
