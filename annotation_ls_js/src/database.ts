import { Database } from 'sqlite3';
import { URI } from 'vscode-uri';
import * as path from 'path';

export class DatabaseManager {
    private connections: Map<string, Database>;
    private currentDb: Database | null;
    private _projectRoot: string | null;
    private maxConnections: number;

    constructor(projectRoot?: string) {
        this.connections = new Map();
        this.currentDb = null;
        this._projectRoot = null;
        this.maxConnections = 5;

        if (projectRoot) {
            this.initDb(projectRoot);
        }
    }

    get projectRoot(): string | null {
        return this._projectRoot;
    }

    initDb(projectRoot: string): void {
        this._projectRoot = projectRoot;
        const dbPath = path.join(projectRoot, '.annotation', 'annotations.db');

        // 创建或获取数据库连接
        const db = new Database(dbPath, (err) => {
            if (err) {
                console.error('Failed to connect to database:', err);
                return;
            }

            // 创建表
            db.exec(`
                CREATE TABLE IF NOT EXISTS files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT UNIQUE NOT NULL
                );

                CREATE TABLE IF NOT EXISTS annotations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_id INTEGER NOT NULL,
                    annotation_id INTEGER NOT NULL,
                    note_file TEXT NOT NULL,
                    FOREIGN KEY (file_id) REFERENCES files (id),
                    UNIQUE (file_id, annotation_id)
                );
            `, (err) => {
                if (err) {
                    console.error('Failed to create tables:', err);
                }
            });
        });

        // 管理连接池
        if (this.connections.size >= this.maxConnections) {
            const oldestKey = Array.from(this.connections.keys())[0];
            if (oldestKey) {
                const oldDb = this.connections.get(oldestKey);
                if (oldDb) {
                    oldDb.close();
                    this.connections.delete(oldestKey);
                }
            }
        }

        this.connections.set(projectRoot, db);
        this.currentDb = db;
    }

    private getConn(): Database {
        if (!this.currentDb) {
            throw new Error('Database not initialized');
        }
        return this.currentDb;
    }

    private uriToRelativePath(uri: string): string {
        if (!this._projectRoot) {
            throw new Error('Project root not set');
        }
        const fsPath = URI.parse(uri).fsPath;
        return path.relative(this._projectRoot, fsPath);
    }

    async getAnnotationNoteFile(fileUri: string, annotationId: number): Promise<string | null> {
        const db = this.getConn();
        const filePath = this.uriToRelativePath(fileUri);

        return new Promise((resolve, reject) => {
            db.get(
                `SELECT note_file
                FROM annotations a
                JOIN files f ON a.file_id = f.id
                WHERE f.file_path = ? AND a.annotation_id = ?`,
                [filePath, annotationId],
                (err, row: { note_file: string } | undefined) => {
                    if (err) {
                        reject(err);
                        return;
                    }
                    resolve(row ? row.note_file : null);
                }
            );
        });
    }

    async createAnnotation(docUri: string, annotationId: number): Promise<void> {
        const db = this.getConn();
        const filePath = this.uriToRelativePath(docUri);
        const noteFile = `note_${Date.now()}.md`;

        return new Promise((resolve, reject) => {
            db.run('BEGIN TRANSACTION', (err) => {
                if (err) {
                    reject(err);
                    return;
                }

                db.get(
                    'SELECT id FROM files WHERE file_path = ?',
                    [filePath],
                    (err, row: { id: number } | undefined) => {
                        if (err) {
                            db.run('ROLLBACK');
                            reject(err);
                            return;
                        }

                        const createAnnotation = (fileId: number) => {
                            db.run(
                                'INSERT INTO annotations (file_id, annotation_id, note_file) VALUES (?, ?, ?)',
                                [fileId, annotationId, noteFile],
                                (err) => {
                                    if (err) {
                                        db.run('ROLLBACK');
                                        reject(err);
                                        return;
                                    }
                                    db.run('COMMIT');
                                    resolve();
                                }
                            );
                        };

                        if (row) {
                            createAnnotation(row.id);
                        } else {
                            db.run(
                                'INSERT INTO files (file_path) VALUES (?)',
                                [filePath],
                                function(err) {
                                    if (err) {
                                        db.run('ROLLBACK');
                                        reject(err);
                                        return;
                                    }
                                    createAnnotation(this.lastID);
                                }
                            );
                        }
                    }
                );
            });
        });
    }

    async getNoteFilesFromSourceUri(sourceUri: string): Promise<string[]> {
        const db = this.getConn();
        const filePath = this.uriToRelativePath(sourceUri);

        return new Promise((resolve, reject) => {
            db.all(
                `SELECT note_file
                FROM annotations a
                JOIN files f ON a.file_id = f.id
                WHERE f.file_path = ?
                ORDER BY a.annotation_id`,
                [filePath],
                (err, rows: { note_file: string }[]) => {
                    if (err) {
                        reject(err);
                        return;
                    }
                    resolve(rows.map(row => row.note_file));
                }
            );
        });
    }

    async deleteAnnotation(fileUri: string, annotationId: number): Promise<void> {
        const db = this.getConn();
        const filePath = this.uriToRelativePath(fileUri);

        return new Promise((resolve, reject) => {
            db.run(
                `DELETE FROM annotations
                WHERE file_id = (
                    SELECT id FROM files WHERE file_path = ?
                ) AND annotation_id = ?`,
                [filePath, annotationId],
                (err) => {
                    if (err) {
                        reject(err);
                    } else {
                        resolve();
                    }
                }
            );
        });
    }

    async increaseAnnotationIds(fileUri: string, fromId: number, increment: number = 1): Promise<void> {
        const db = this.getConn();
        const filePath = this.uriToRelativePath(fileUri);

        return new Promise((resolve, reject) => {
            db.run('BEGIN TRANSACTION', (err) => {
                if (err) {
                    reject(err);
                    return;
                }

                db.get(
                    'SELECT id FROM files WHERE file_path = ?',
                    [filePath],
                    (err, row: { id: number } | undefined) => {
                        if (err || !row) {
                            db.run('ROLLBACK');
                            reject(err || new Error('File not found'));
                            return;
                        }

                        const fileId = row.id;
                        db.all(
                            `SELECT annotation_id, note_file
                            FROM annotations
                            WHERE file_id = ? AND annotation_id >= ?
                            ORDER BY annotation_id DESC`,
                            [fileId, fromId],
                            (err, rows: { annotation_id: number, note_file: string }[]) => {
                                if (err) {
                                    db.run('ROLLBACK');
                                    reject(err);
                                    return;
                                }

                                if (increment < 0) {
                                    rows.reverse();
                                }

                                const updatePromises = rows.map(({ annotation_id, note_file }) => {
                                    return new Promise<void>((resolve, reject) => {
                                        db.run(
                                            `UPDATE annotations
                                            SET annotation_id = annotation_id + ?
                                            WHERE file_id = ? AND annotation_id = ?`,
                                            [increment, fileId, annotation_id],
                                            (err) => {
                                                if (err) {
                                                    reject(err);
                                                } else {
                                                    resolve();
                                                }
                                            }
                                        );
                                    });
                                });

                                Promise.all(updatePromises)
                                    .then(() => {
                                        db.run('COMMIT');
                                        resolve();
                                    })
                                    .catch((err) => {
                                        db.run('ROLLBACK');
                                        reject(err);
                                    });
                            }
                        );
                    }
                );
            });
        });
    }
}
