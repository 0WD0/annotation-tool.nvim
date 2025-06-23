import { DatabaseManager } from '../../src/database';
import * as path from 'path';
import * as fs from 'fs/promises';
import * as sqlite3 from 'sqlite3';

// 模拟sqlite3和fs模块
jest.mock('sqlite3');
jest.mock('fs/promises');

// 禁用控制台错误输出，减少测试输出噪音
jest.spyOn(console, 'error').mockImplementation(() => {});

const mockedFs = fs as jest.Mocked<typeof fs>;
const mockedSqlite = sqlite3 as jest.Mocked<typeof sqlite3>;

describe('DatabaseManager', () => {
  let dbManager: DatabaseManager;
  const testRootPath = '/test/root/path';
  const testDbPath = path.join(testRootPath, '.annotations', 'annotations.db');

  // 模拟数据库和语句
  const mockDb = {
    run: jest.fn(),
    get: jest.fn(),
    all: jest.fn(),
    prepare: jest.fn(),
    close: jest.fn(),
    exec: jest.fn()
  };

  const mockStmt = {
    run: jest.fn(),
    get: jest.fn(),
    all: jest.fn(),
    finalize: jest.fn()
  };

  beforeEach(() => {
    // 重置所有模拟
    jest.resetAllMocks();
    
    // 模拟mkdir方法
    mockedFs.mkdir.mockResolvedValue(undefined);
    
    // 模拟sqlite3.Database
    (mockedSqlite.Database as any) = jest.fn().mockImplementation((_, callback) => {
      callback(null);
      return mockDb;
    });
    
    // 模拟prepare方法
    mockDb.prepare.mockReturnValue(mockStmt);
    
    // 创建DatabaseManager实例
    dbManager = new DatabaseManager(testRootPath);
  });

  describe('getDb', () => {
    it('should create database directory and initialize tables', async () => {
      // 模拟exec方法成功
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      await dbManager.getDb();
      
      expect(mockedFs.mkdir).toHaveBeenCalledWith(path.dirname(testDbPath), { recursive: true });
      expect(mockedSqlite.Database).toHaveBeenCalledWith(testDbPath, expect.any(Function));
      expect(mockDb.exec).toHaveBeenCalledTimes(1);
      expect(mockDb.exec.mock.calls[0][0]).toContain('CREATE TABLE IF NOT EXISTS annotations');
    });

    it('should handle database creation errors', async () => {
      // 模拟sqlite3.Database失败
      const dbError = new Error('Failed to create database');
      (mockedSqlite.Database as any) = jest.fn().mockImplementation((_, callback) => {
        callback(dbError);
        return mockDb;
      });
      
      await expect(dbManager.getDb()).rejects.toThrow(dbError);
    });

    it('should handle table creation errors', async () => {
      // 模拟exec方法失败
      const execError = new Error('Failed to create table');
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(execError);
      });
      
      await expect(dbManager.getDb()).rejects.toThrow(execError);
    });
  });

  describe('saveAnnotation', () => {
    it('should save annotation to database', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟run方法成功
      mockStmt.run.mockImplementation((params, callback) => {
        if (callback) callback(null);
      });
      
      const uri = 'file:///test/file.txt';
      const annotationId = 1;
      const range = { start: { line: 0, character: 0 }, end: { line: 0, character: 10 } };
      const noteFile = 'annotation_1.md';
      
      const result = await dbManager.saveAnnotation(uri, annotationId, range, noteFile);
      
      expect(result).toBe(true);
      expect(mockDb.prepare).toHaveBeenCalled();
      expect(mockStmt.run).toHaveBeenCalledWith(
        expect.anything(),
        expect.any(Function)
      );
    });

    it('should handle database errors when saving annotation', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟run方法失败
      const runError = new Error('Failed to save annotation');
      mockStmt.run.mockImplementation((params, callback) => {
        if (callback) callback(runError);
      });
      
      const result = await dbManager.saveAnnotation('uri', 1, { start: { line: 0, character: 0 }, end: { line: 0, character: 10 } }, 'note.md');
      
      expect(result).toBe(false);
    });
  });

  describe('getAnnotations', () => {
    it('should retrieve annotations for a file', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟all方法成功
      const mockAnnotations = [
        { id: 1, start_line: 0, start_character: 0, end_line: 0, end_character: 10, note_file: 'annotation_1.md' },
        { id: 2, start_line: 1, start_character: 0, end_line: 1, end_character: 20, note_file: 'annotation_2.md' }
      ];
      mockStmt.all.mockImplementation((params, callback) => {
        if (callback) callback(null, mockAnnotations);
      });
      
      const uri = 'file:///test/file.txt';
      const result = await dbManager.getAnnotations(uri);
      
      expect(result).toHaveLength(2);
      expect(result[0]).toEqual(expect.objectContaining({
        id: 1,
        start: { line: 0, character: 0 },
        end: { line: 0, character: 10 },
        noteFile: 'annotation_1.md'
      }));
    });

    it('should handle database errors when retrieving annotations', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟all方法失败
      const allError = new Error('Failed to retrieve annotations');
      mockStmt.all.mockImplementation((params, callback) => {
        if (callback) callback(allError, null);
      });
      
      const result = await dbManager.getAnnotations('uri');
      
      expect(result).toEqual([]);
    });
  });

  describe('annotationExists', () => {
    it('should return true if annotation exists', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟get方法成功
      mockStmt.get.mockImplementation((params, callback) => {
        if (callback) callback(null, { count: 1 });
      });
      
      const uri = 'file:///test/file.txt';
      const annotationId = 1;
      
      const result = await dbManager.annotationExists(uri, annotationId);
      
      expect(result).toBe(true);
    });

    it('should return false if annotation does not exist', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟get方法成功但没有找到记录
      mockStmt.get.mockImplementation((params, callback) => {
        if (callback) callback(null, { count: 0 });
      });
      
      const result = await dbManager.annotationExists('uri', 1);
      
      expect(result).toBe(false);
    });

    it('should handle database errors when checking if annotation exists', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟get方法失败
      const getError = new Error('Failed to check if annotation exists');
      mockStmt.get.mockImplementation((params, callback) => {
        if (callback) callback(getError, null);
      });
      
      const result = await dbManager.annotationExists('uri', 1);
      
      expect(result).toBe(false);
    });
  });

  describe('deleteAnnotation', () => {
    it('should delete annotation from database', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟run方法成功
      mockStmt.run.mockImplementation((params, callback) => {
        if (callback) callback(null);
      });
      
      const uri = 'file:///test/file.txt';
      const annotationId = 1;
      
      const result = await dbManager.deleteAnnotation(uri, annotationId);
      
      expect(result).toBe(true);
    });

    it('should handle database errors when deleting annotation', async () => {
      // 模拟getDb方法
      mockDb.exec.mockImplementation((_, callback) => {
        if (callback) callback(null);
      });
      
      // 模拟run方法失败
      const runError = new Error('Failed to delete annotation');
      mockStmt.run.mockImplementation((params, callback) => {
        if (callback) callback(runError);
      });
      
      const result = await dbManager.deleteAnnotation('uri', 1);
      
      expect(result).toBe(false);
    });
  });
});
