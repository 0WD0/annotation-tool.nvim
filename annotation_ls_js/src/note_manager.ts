import * as path from 'path';
import * as fs from 'fs/promises';
import { URI } from 'vscode-uri';
import matter from 'gray-matter';

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

    /**
     * 创建带 frontmatter 的标注笔记
     * @param sourceUri 源文件URI
     * @param annotationId 标注ID
     * @param selectedText 选中的文本
     * @param noteFileName 笔记文件名
     */
    async createAnnotationNoteWithFrontmatter(
        sourceUri: string, 
        annotationId: number, 
        selectedText: string, 
        noteFileName: string
    ): Promise<string> {
        try {
            // 获取相对路径
            const sourcePath = URI.parse(sourceUri).fsPath;
            const relativePath = path.relative(this.rootPath, sourcePath);
            
            // 创建带 frontmatter 的内容
            const frontmatterData = {
                file: relativePath.replace(/\\/g, '/'), // 确保使用前斜杠
                id: annotationId
            };
            
            const noteContent = matter.stringify(`\`\`\`\n${selectedText}\n\`\`\`\n\n`, frontmatterData);
            
            // 确保笔记目录存在
            await this.init();
            
            // 写入文件
            const notePath = path.join(this.notesDir, noteFileName);
            await fs.writeFile(notePath, noteContent, { encoding: 'utf8' });
            
            return notePath;
        } catch (err) {
            console.error('Error creating annotation note with frontmatter:', err);
            throw err;
        }
    }

    /**
     * 从笔记文件解析标注信息
     * @param noteUri 笔记文件URI
     */
    async parseNoteFile(noteUri: string): Promise<{ annotationId: number; sourceUri: string } | null> {
        try {
            const notePath = URI.parse(noteUri).fsPath;
            const content = await fs.readFile(notePath, 'utf-8');
            
            // 解析 frontmatter
            const parsed = matter(content);
            
            if (!parsed.data.file || !parsed.data.id) {
                // 如果没有 frontmatter，尝试从文件名解析
                const fileName = path.basename(notePath, '.md');
                const match = fileName.match(/annotation_(\d+)/);
                if (match) {
                    const annotationId = parseInt(match[1], 10);
                    // 这种情况下无法确定源文件，返回 null
                    return null;
                }
                return null;
            }
            
            const annotationId = parsed.data.id;
            const relativePath = parsed.data.file;
            
            // 将相对路径转换为绝对路径，然后转换为URI
            const absolutePath = path.resolve(this.rootPath, relativePath);
            const sourceUri = URI.file(absolutePath).toString();
            
            return { annotationId, sourceUri };
        } catch (err) {
            console.error('Error parsing note file:', err);
            return null;
        }
    }

    /**
     * 获取笔记目录路径
     * @param rootPath 可选的根路径
     */
    getNotesDir(rootPath?: string): string {
        if (rootPath) {
            return path.join(rootPath, '.annotation', 'notes');
        }
        return this.notesDir;
    }

    /**
     * 提取笔记内容中的 Notes 部分
     * @param content 笔记内容
     */
    extractNotesContent(content: string): string {
        try {
            // 查找 ## Notes 标题
            const lines = content.split('\n');
            let notesStartIndex = -1;
            
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].trim().startsWith('## Notes')) {
                    notesStartIndex = i + 1;
                    break;
                }
            }
            
            if (notesStartIndex === -1) {
                return '';
            }
            
            // 返回 ## Notes 后的所有内容
            return lines.slice(notesStartIndex).join('\n').trim();
        } catch (err) {
            console.error('Error extracting notes content:', err);
            return '';
        }
    }
}
