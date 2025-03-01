import * as path from 'path';
import * as fs from 'fs/promises';
import { URI } from 'vscode-uri';

/**
 * 笔记管理器类
 */
export class NoteManager {
    private rootPath: string;
    private notesDir: string;

    /**
     * 构造函数
     * @param rootPath 根路径
     */
    constructor(rootPath: string) {
        this.rootPath = rootPath;
        this.notesDir = path.join(rootPath, '.annotations', 'notes');
    }

    /**
     * 初始化笔记目录
     */
    async init(): Promise<void> {
        try {
            // 确保笔记目录存在
            await fs.mkdir(this.notesDir, { recursive: true });
        } catch (err) {
            console.error('Failed to initialize notes directory:', err);
            throw err;
        }
    }

    /**
     * 创建标注笔记
     * @param annotationId 标注ID
     * @param initialContent 初始内容
     */
    async createAnnotationNote(annotationId: number, initialContent: string = ''): Promise<string> {
        try {
            console.log(`Creating annotation note for ID ${annotationId} with content length: ${initialContent.length}`);
            
            // 确保笔记目录存在
            await this.init();
            
            // 生成笔记文件名
            const noteFile = `annotation_${annotationId}.md`;
            const notePath = path.join(this.notesDir, noteFile);
            
            console.log(`Writing to note file: ${notePath}`);
            console.log(`Content to write: ${initialContent.substring(0, 50)}${initialContent.length > 50 ? '...' : ''}`);
            
            // 写入初始内容
            await fs.writeFile(notePath, initialContent, { encoding: 'utf8' });
            
            // Verify the file was written correctly
            const stats = await fs.stat(notePath);
            console.log(`Note file created with size: ${stats.size} bytes`);
            
            return noteFile;
        } catch (err) {
            console.error('Error creating annotation note:', err);
            throw err;
        }
    }

    /**
     * 获取笔记文件路径
     * @param noteFile 笔记文件名
     */
    getNotePath(noteFile: string): string {
        return path.join(this.notesDir, noteFile);
    }

    /**
     * 获取笔记内容
     * @param noteFile 笔记文件名
     */
    async getNoteContent(noteFile: string): Promise<string> {
        try {
            const notePath = this.getNotePath(noteFile);
            
            // 检查文件是否存在
            try {
                await fs.access(notePath);
            } catch (err) {
                return '';
            }
            
            // 读取文件内容
            const content = await fs.readFile(notePath, 'utf-8');
            return content;
        } catch (err) {
            console.error('Error reading note content:', err);
            return '';
        }
    }

    /**
     * 更新笔记内容
     * @param noteFile 笔记文件名
     * @param content 新内容
     */
    async updateNoteContent(noteFile: string, content: string): Promise<boolean> {
        try {
            const notePath = this.getNotePath(noteFile);
            
            // 写入新内容
            await fs.writeFile(notePath, content);
            
            return true;
        } catch (err) {
            console.error('Error updating note content:', err);
            return false;
        }
    }

    /**
     * 删除标注笔记
     * @param noteFile 笔记文件名
     */
    async deleteAnnotationNote(noteFile: string): Promise<boolean> {
        try {
            const notePath = this.getNotePath(noteFile);
            
            // 检查文件是否存在
            try {
                await fs.access(notePath);
            } catch (err) {
                // 文件不存在，视为删除成功
                return true;
            }
            
            // 删除文件
            await fs.unlink(notePath);
            
            return true;
        } catch (err) {
            console.error('Error deleting note:', err);
            return false;
        }
    }

    /**
     * 搜索笔记
     * @param query 搜索关键词
     */
    async searchNotes(query: string): Promise<Array<{ file: string; content: string }>> {
        try {
            // 读取所有笔记文件
            const files = await fs.readdir(this.notesDir);
            const noteFiles = files.filter(file => file.endsWith('.md'));
            
            const results: Array<{ file: string; content: string }> = [];
            
            // 搜索每个文件
            for (const noteFile of noteFiles) {
                const content = await this.getNoteContent(noteFile);
                
                // 如果内容包含查询词，添加到结果中
                if (content.toLowerCase().includes(query.toLowerCase())) {
                    results.push({
                        file: noteFile,
                        content
                    });
                }
            }
            
            return results;
        } catch (err) {
            console.error('Error searching notes:', err);
            return [];
        }
    }
}
