import * as path from 'path';
import { URI } from 'vscode-uri';

/**
 * 工作区类
 */
export class Workspace {
    private _uri: string;
    private _rootPath: string;

    /**
     * 构造函数
     * @param uri 工作区URI
     * @param rootPath 工作区根路径
     */
    constructor(uri: string, rootPath: string) {
        this._uri = uri;
        this._rootPath = rootPath;
    }

    /**
     * 获取工作区URI
     */
    get uri(): string {
        return this._uri;
    }

    /**
     * 获取工作区根路径
     */
    get rootPath(): string {
        return this._rootPath;
    }

    /**
     * 检查文件是否在工作区内
     * @param fileUri 文件URI
     */
    containsFile(fileUri: string): boolean {
        try {
            const filePath = URI.parse(fileUri).fsPath;
            const relativePath = path.relative(this._rootPath, filePath);
            
            // 如果相对路径以 '..' 开头，则文件不在工作区内
            return !relativePath.startsWith('..');
        } catch (error) {
            console.error(`Error checking if file is in workspace: ${error}`);
            return false;
        }
    }
}

/**
 * 工作区管理器类
 */
export class WorkspaceManager {
    private workspaces: Workspace[];

    /**
     * 构造函数
     */
    constructor() {
        this.workspaces = [];
    }

    /**
     * 添加工作区
     * @param uri 工作区URI
     * @param rootPath 工作区根路径
     */
    addWorkspace(uri: string, rootPath: string): Workspace {
        try {
            // 检查是否已存在相同URI的工作区
            const existingWorkspace = this.workspaces.find(ws => ws.uri === uri);
            if (existingWorkspace) {
                return existingWorkspace;
            }
            
            // 创建新工作区
            const workspace = new Workspace(uri, rootPath);
            this.workspaces.push(workspace);
            
            return workspace;
        } catch (error) {
            console.error(`Failed to add workspace: ${error}`);
            throw error;
        }
    }

    /**
     * 移除工作区
     * @param uri 工作区URI
     */
    removeWorkspace(uri: string): boolean {
        try {
            const initialLength = this.workspaces.length;
            this.workspaces = this.workspaces.filter(ws => ws.uri !== uri);
            
            return this.workspaces.length < initialLength;
        } catch (error) {
            console.error(`Failed to remove workspace: ${error}`);
            return false;
        }
    }

    /**
     * 获取包含指定文件的工作区
     * @param fileUri 文件URI
     */
    getWorkspaceForFile(fileUri: string): Workspace | null {
        try {
            // 查找包含该文件的工作区
            for (const workspace of this.workspaces) {
                if (workspace.containsFile(fileUri)) {
                    return workspace;
                }
            }
            
            return null;
        } catch (error) {
            console.error(`Failed to get workspace for file: ${error}`);
            return null;
        }
    }

    /**
     * 获取包含指定URI的工作区（兼容方法）
     * @param uri 文件或工作区URI
     */
    getWorkspace(uri: string): Workspace | null {
        // 首先尝试作为工作区URI直接匹配
        const directMatch = this.workspaces.find(ws => ws.uri === uri);
        if (directMatch) {
            return directMatch;
        }
        
        // 如果没有直接匹配，尝试作为文件URI查找包含它的工作区
        return this.getWorkspaceForFile(uri);
    }

    /**
     * 获取所有工作区
     */
    getAllWorkspaces(): Workspace[] {
        return [...this.workspaces];
    }
}

// 全局工作区管理器实例
export const workspaceManager = new WorkspaceManager();
