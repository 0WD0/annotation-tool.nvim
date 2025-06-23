import { URI } from 'vscode-uri';
import * as path from 'path';
import * as fs from 'fs/promises';
import * as yaml from 'yaml';

interface NoteMetadata {
    file: string;
    id: number;
}

export class NoteManager {
    private projectRoot: string | null;
    private notesDir: string | null;

    constructor(projectRoot?: string) {
        this.projectRoot = null;
        this.notesDir = null;
        if (projectRoot) {
            this.init(projectRoot);
        }
    }

    init(projectRoot: string): void {
        this.projectRoot = projectRoot;
        this.notesDir = path.join(projectRoot, '.annotation', 'notes');
    }

    private uriToPath(uri: string): string {
        return URI.parse(uri).fsPath;
    }

    async getAnnotationIdFromNoteUri(noteUri: string): Promise<number | null> {
        try {
            if (!this.notesDir) {
                throw new Error('Notes directory not set');
            }

            const notePath = this.uriToPath(noteUri);
            // 检查路径是否在笔记目录下
            path.relative(this.notesDir, notePath);

            // 读取笔记内容获取 annotation id
            const content = await fs.readFile(notePath, 'utf-8');
            const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
            if (!frontmatterMatch) {
                throw new Error('No frontmatter found');
            }

            const metadata = yaml.parse(frontmatterMatch[1]) as NoteMetadata;
            if (metadata.id === undefined) {
                throw new Error('Annotation id not found');
            }

            return metadata.id;
        } catch (err) {
            console.error('Failed to get annotation id:', err);
            return null;
        }
    }

    async getSourcePathFromNoteUri(noteUri: string): Promise<string | null> {
        try {
            if (!this.notesDir) {
                throw new Error('Notes directory not set');
            }

            const notePath = this.uriToPath(noteUri);
            // 检查路径是否在笔记目录下
            path.relative(this.notesDir, notePath);

            // 读取笔记内容
            const content = await fs.readFile(notePath, 'utf-8');
            const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
            if (!frontmatterMatch) {
                throw new Error('No frontmatter found');
            }

            const metadata = yaml.parse(frontmatterMatch[1]) as NoteMetadata;
            if (!metadata.file) {
                return null;
            }

            // 确保返回绝对路径
            let sourcePath = metadata.file;
            if (!path.isAbsolute(sourcePath) && this.projectRoot) {
                sourcePath = path.join(this.projectRoot, sourcePath);
            }
            return sourcePath;
        } catch (err) {
            console.error('Failed to get source path:', err);
            return null;
        }
    }

    async updateNoteSource(notePath: string, filePath: string): Promise<void> {
        try {
            const content = await fs.readFile(notePath, 'utf-8');
            const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
            if (!frontmatterMatch) {
                throw new Error('No frontmatter found');
            }

            const metadata = yaml.parse(frontmatterMatch[1]) as NoteMetadata;
            metadata.file = filePath;

            const newContent = content.replace(
                /^---\n[\s\S]*?\n---/,
                `---\n${yaml.stringify(metadata)}---`
            );

            await fs.writeFile(notePath, newContent, 'utf-8');
        } catch (err) {
            console.error('Failed to update note source:', err);
        }
    }

    async updateNoteAid(notePath: string, annotationId: number): Promise<void> {
        try {
            const content = await fs.readFile(notePath, 'utf-8');
            const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
            if (!frontmatterMatch) {
                throw new Error('No frontmatter found');
            }

            const metadata = yaml.parse(frontmatterMatch[1]) as NoteMetadata;
            metadata.id = annotationId;

            const newContent = content.replace(
                /^---\n[\s\S]*?\n---/,
                `---\n${yaml.stringify(metadata)}---`
            );

            await fs.writeFile(notePath, newContent, 'utf-8');
        } catch (err) {
            console.error('Failed to update note aid:', err);
        }
    }

    async searchNotes(query: string, searchType: 'file_path' | 'content' | 'note' | 'all'): Promise<Array<{
        file: string;
        note_file: string;
        original_text: string;
        note_content: string;
    }>> {
        if (!this.notesDir) {
            return [];
        }

        try {
            const results = [];
            const files = await fs.readdir(this.notesDir);

            for (const file of files) {
                if (!file.endsWith('.md')) {
                    continue;
                }

                const notePath = path.join(this.notesDir, file);
                const content = await fs.readFile(notePath, 'utf-8');
                const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
                if (!frontmatterMatch) {
                    continue;
                }

                const metadata = yaml.parse(frontmatterMatch[1]) as NoteMetadata;
                const noteContent = content.replace(/^---\n[\s\S]*?\n---/, '').trim();

                // 根据搜索类型进行匹配
                let matched = false;
                const lowerQuery = query.toLowerCase();

                if (searchType === 'file_path' || searchType === 'all') {
                    matched = metadata.file.toLowerCase().includes(lowerQuery);
                }
                if (!matched && (searchType === 'content' || searchType === 'all')) {
                    matched = noteContent.toLowerCase().includes(lowerQuery);
                }
                if (!matched && (searchType === 'note' || searchType === 'all')) {
                    matched = noteContent.toLowerCase().includes(lowerQuery);
                }

                if (matched) {
                    results.push({
                        file: metadata.file,
                        note_file: file,
                        original_text: '',
                        note_content: noteContent
                    });
                }
            }

            return results;
        } catch (err) {
            console.error('Failed to search notes:', err);
            return [];
        }
    }
}
