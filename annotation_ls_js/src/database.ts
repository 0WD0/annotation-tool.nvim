import { Database } from 'sqlite3';
import { URI } from 'vscode-uri';
import * as path from 'path';
import * as fs from 'fs/promises';

/**
 * 数据库管理器类
 */
export class DatabaseManager {
    private rootPath: string;
    private dbPath: string;
    private db: Database | null = null;

    /**
     * 构造函数
     * @param rootPath 根路径
     */
    constructor(rootPath: string) {
        this.rootPath = rootPath;
        this.dbPath = path.join(rootPath, '.annotations', 'annotations.db');
    }

    /**
     * 获取数据库连接
     */
    async getDb(): Promise<Database> {
        if (this.db) {
            return this.db;
        }

        // 确保数据库目录存在
        const dbDir = path.dirname(this.dbPath);
        try {
            await fs.mkdir(dbDir, { recursive: true });
        } catch (err) {
            console.error('Failed to create database directory:', err);
            throw err;
        }

        // 创建数据库连接
        return new Promise((resolve, reject) => {
            try {
                const db = new Database(this.dbPath, (err) => {
                    if (err) {
                        console.error('Failed to connect to database:', err);
                        reject(err);
                        return;
                    }

                    this.db = db;

                    // 创建表
                    db.exec(`
                        CREATE TABLE IF NOT EXISTS annotations (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            file_uri TEXT NOT NULL,
                            annotation_id INTEGER NOT NULL,
                            start_line INTEGER NOT NULL,
                            start_character INTEGER NOT NULL,
                            end_line INTEGER NOT NULL,
                            end_character INTEGER NOT NULL,
                            note_file TEXT,
                            UNIQUE(file_uri, annotation_id)
                        )
                    `, (err) => {
                        if (err) {
                            console.error('Failed to create tables:', err);
                            reject(err);
                            return;
                        }

                        resolve(db);
                    });
                });
            } catch (err) {
                reject(err);
            }
        });
    }

    /**
     * 保存标注
     * @param fileUri 文件URI
     * @param annotationId 标注ID
     * @param range 标注范围
     * @param noteFile 笔记文件名
     */
    async saveAnnotation(
        fileUri: string,
        annotationId: number,
        range: { start: { line: number, character: number }, end: { line: number, character: number } },
        noteFile: string
    ): Promise<boolean> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.run(
                    `INSERT OR REPLACE INTO annotations 
                    (file_uri, annotation_id, start_line, start_character, end_line, end_character, note_file) 
                    VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    [
                        fileUri,
                        annotationId,
                        range.start.line,
                        range.start.character,
                        range.end.line,
                        range.end.character,
                        noteFile
                    ],
                    function(err) {
                        if (err) {
                            console.error('Failed to save annotation:', err);
                            resolve(false);
                            return;
                        }
                        resolve(true);
                    }
                );
            });
        } catch (err) {
            console.error('Error saving annotation:', err);
            return false;
        }
    }

    /**
     * 获取标注笔记文件
     * @param fileUri 文件URI
     * @param annotationId 标注ID
     */
    async getAnnotationNoteFile(fileUri: string, annotationId: number): Promise<string | null> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.get(
                    `SELECT note_file FROM annotations WHERE file_uri = ? AND annotation_id = ?`,
                    [fileUri, annotationId],
                    (err, row: { note_file: string } | undefined) => {
                        if (err) {
                            console.error('Failed to get annotation note file:', err);
                            resolve(null);
                            return;
                        }

                        if (!row) {
                            resolve(null);
                            return;
                        }

                        resolve(row.note_file);
                    }
                );
            });
        } catch (err) {
            console.error('Error getting annotation note file:', err);
            return null;
        }
    }

    /**
     * 检查标注是否存在
     * @param fileUri 文件URI
     * @param annotationId 标注ID
     */
    async annotationExists(fileUri: string, annotationId: number): Promise<boolean> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.get(
                    `SELECT 1 FROM annotations WHERE file_uri = ? AND annotation_id = ?`,
                    [fileUri, annotationId],
                    (err, row) => {
                        if (err) {
                            console.error('Failed to check annotation existence:', err);
                            resolve(false);
                            return;
                        }

                        resolve(!!row);
                    }
                );
            });
        } catch (err) {
            console.error('Error checking annotation existence:', err);
            return false;
        }
    }

    /**
     * 删除标注
     * @param fileUri 文件URI
     * @param annotationId 标注ID
     */
    async deleteAnnotation(fileUri: string, annotationId: number): Promise<boolean> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.run(
                    `DELETE FROM annotations WHERE file_uri = ? AND annotation_id = ?`,
                    [fileUri, annotationId],
                    function(err) {
                        if (err) {
                            console.error('Failed to delete annotation:', err);
                            resolve(false);
                            return;
                        }
                        resolve(this.changes > 0);
                    }
                );
            });
        } catch (err) {
            console.error('Error deleting annotation:', err);
            return false;
        }
    }

    /**
     * 获取文件中的所有标注
     * @param fileUri 文件URI
     */
    async getAnnotations(fileUri: string): Promise<{ id: number, range: { start: { line: number, character: number }, end: { line: number, character: number } }, noteFile: string }[]> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.all(
                    `SELECT * FROM annotations WHERE file_uri = ? ORDER BY annotation_id`,
                    [fileUri],
                    (err, rows) => {
                        if (err) {
                            console.error('Failed to get annotations:', err);
                            resolve([]);
                            return;
                        }

                        resolve(rows.map((row: any) => ({
                            id: row.annotation_id,
                            range: {
                                start: {
                                    line: row.start_line,
                                    character: row.start_character
                                },
                                end: {
                                    line: row.end_line,
                                    character: row.end_character
                                }
                            },
                            noteFile: row.note_file
                        })));
                    }
                );
            });
        } catch (err) {
            console.error('Error getting annotations:', err);
            return [];
        }
    }

    /**
     * 增加指定 ID 之后的所有标注 ID
     * @param fileUri 文件URI
     * @param fromId 起始ID
     */
    async increaseAnnotationIds(fileUri: string, fromId: number): Promise<boolean> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.run(
                    `UPDATE annotations SET annotation_id = annotation_id + 1 
                    WHERE file_uri = ? AND annotation_id >= ?
                    ORDER BY annotation_id DESC`,
                    [fileUri, fromId],
                    function(err) {
                        if (err) {
                            console.error('Failed to increase annotation IDs:', err);
                            resolve(false);
                            return;
                        }
                        resolve(this.changes > 0);
                    }
                );
            });
        } catch (err) {
            console.error('Error increasing annotation IDs:', err);
            return false;
        }
    }

    /**
     * 获取源文件的所有笔记文件
     * @param sourceUri 源文件URI
     */
    async getNoteFilesFromSourceUri(sourceUri: string): Promise<string[]> {
        try {
            const db = await this.getDb();

            return new Promise((resolve, reject) => {
                db.all(
                    `SELECT note_file FROM annotations WHERE file_uri = ? ORDER BY annotation_id`,
                    [sourceUri],
                    (err, rows) => {
                        if (err) {
                            console.error('Failed to get note files from source URI:', err);
                            resolve([]);
                            return;
                        }

                        resolve(rows.map((row: any) => row.note_file).filter(Boolean));
                    }
                );
            });
        } catch (err) {
            console.error('Error getting note files from source URI:', err);
            return [];
        }
    }

    /**
     * 关闭数据库连接
     */
    async close(): Promise<void> {
        if (this.db) {
            return new Promise((resolve, reject) => {
                this.db!.close(err => {
                    if (err) {
                        console.error('Failed to close database:', err);
                        reject(err);
                        return;
                    }
                    this.db = null;
                    resolve();
                });
            });
        }
    }
}
