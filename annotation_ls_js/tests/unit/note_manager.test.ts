import * as path from 'path';
import * as fs from 'fs/promises';
import { NoteManager } from '../../src/note_manager';

// 模拟fs模块
jest.mock('fs/promises');
const mockedFs = fs as jest.Mocked<typeof fs>;

// 禁用控制台输出，减少测试输出噪音
jest.spyOn(console, 'log').mockImplementation(() => {});
jest.spyOn(console, 'error').mockImplementation(() => {});

describe('NoteManager', () => {
  let noteManager: NoteManager;
  const testRootPath = '/test/root/path';
  const testNotesDir = path.join(testRootPath, '.annotations', 'notes');

  beforeEach(() => {
    // 重置所有模拟
    jest.resetAllMocks();
    
    // 模拟mkdir方法
    mockedFs.mkdir.mockResolvedValue(undefined);
    
    // 创建NoteManager实例
    noteManager = new NoteManager(testRootPath);
  });

  describe('init', () => {
    it('should create notes directory if it does not exist', async () => {
      await noteManager.init();
      
      expect(mockedFs.mkdir).toHaveBeenCalledWith(testNotesDir, { recursive: true });
    });

    it('should handle errors when creating directory', async () => {
      const error = new Error('Failed to create directory');
      mockedFs.mkdir.mockRejectedValue(error);
      
      await expect(noteManager.init()).rejects.toThrow(error);
    });
  });

  describe('createAnnotationNote', () => {
    it('should create a note file with the given ID and content', async () => {
      // 模拟writeFile和stat方法
      mockedFs.writeFile.mockResolvedValue(undefined);
      mockedFs.stat.mockResolvedValue({ size: 100 } as any);
      
      const annotationId = 42;
      const initialContent = '# Test Annotation\n\nThis is a test.';
      
      const result = await noteManager.createAnnotationNote(annotationId, initialContent);
      
      expect(result).toBe(`annotation_${annotationId}.md`);
      expect(mockedFs.writeFile).toHaveBeenCalledWith(
        path.join(testNotesDir, `annotation_${annotationId}.md`),
        initialContent,
        expect.anything()
      );
    });

    it('should handle errors when writing file', async () => {
      // 模拟init方法成功
      mockedFs.mkdir.mockResolvedValue(undefined);
      
      // 模拟writeFile方法失败
      const error = new Error('Failed to write file');
      mockedFs.writeFile.mockRejectedValue(error);
      
      await expect(noteManager.createAnnotationNote(1, 'content')).rejects.toThrow(error);
    });
  });

  describe('getNoteContent', () => {
    it('should return the content of the note file', async () => {
      const noteFile = 'annotation_1.md';
      const noteContent = '# Annotation 1\n\nThis is the content.';
      
      // 模拟access和readFile方法
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.readFile.mockResolvedValue(Buffer.from(noteContent));
      
      const result = await noteManager.getNoteContent(noteFile);
      
      expect(result).toBe(noteContent);
      expect(mockedFs.readFile).toHaveBeenCalledWith(
        path.join(testNotesDir, noteFile),
        'utf-8'
      );
    });

    it('should return empty string if file does not exist', async () => {
      // 模拟access方法失败
      mockedFs.access.mockRejectedValue(new Error('File not found'));
      
      const result = await noteManager.getNoteContent('non_existent.md');
      
      expect(result).toBe('');
      expect(mockedFs.readFile).not.toHaveBeenCalled();
    });
  });

  describe('updateNoteContent', () => {
    it('should update the content of the note file', async () => {
      const noteFile = 'annotation_1.md';
      const newContent = '# Updated Content';
      
      // 模拟access和writeFile方法
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.writeFile.mockResolvedValue(undefined);
      
      const result = await noteManager.updateNoteContent(noteFile, newContent);
      
      expect(result).toBe(true);
      expect(mockedFs.writeFile).toHaveBeenCalledWith(
        path.join(testNotesDir, noteFile),
        newContent
      );
    });

    it('should return false if file does not exist', async () => {
      // 模拟writeFile方法失败
      mockedFs.writeFile.mockRejectedValue(new Error('File not found'));
      
      const result = await noteManager.updateNoteContent('non_existent.md', 'content');
      
      expect(result).toBe(false);
    });
  });

  describe('deleteAnnotationNote', () => {
    it('should delete the note file', async () => {
      const noteFile = 'annotation_1.md';
      
      // 模拟access和unlink方法
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.unlink.mockResolvedValue(undefined);
      
      const result = await noteManager.deleteAnnotationNote(noteFile);
      
      expect(result).toBe(true);
      expect(mockedFs.unlink).toHaveBeenCalledWith(
        path.join(testNotesDir, noteFile)
      );
    });

    it('should return false if file does not exist', async () => {
      // 模拟unlink方法失败
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.unlink.mockRejectedValue(new Error('File not found'));
      
      const result = await noteManager.deleteAnnotationNote('non_existent.md');
      
      expect(result).toBe(false);
    });
  });

  describe('searchNotes', () => {
    it('should return all note files that match the query', async () => {
      const noteFiles = ['annotation_1.md', 'annotation_2.md', 'annotation_3.md'];
      
      // 模拟readdir方法
      mockedFs.readdir.mockResolvedValue(noteFiles as any);
      
      // 模拟getNoteContent方法返回的内容
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.readFile.mockImplementation((path) => {
        if (path.toString().includes('annotation_1.md')) {
          return Promise.resolve(Buffer.from('Content with test query'));
        } else if (path.toString().includes('annotation_2.md')) {
          return Promise.resolve(Buffer.from('Content without match'));
        } else {
          return Promise.resolve(Buffer.from('Another test query match'));
        }
      });
      
      const result = await noteManager.searchNotes('test query');
      
      expect(result).toHaveLength(2);
      expect(result[0].file).toBe('annotation_1.md');
      expect(result[1].file).toBe('annotation_3.md');
    });

    it('should return empty array if no notes match the query', async () => {
      // 模拟readdir方法
      mockedFs.readdir.mockResolvedValue(['annotation_1.md'] as any);
      
      // 模拟getNoteContent方法返回的内容
      mockedFs.access.mockResolvedValue(undefined);
      mockedFs.readFile.mockResolvedValue(Buffer.from('Content without match'));
      
      const result = await noteManager.searchNotes('non-existent query');
      
      expect(result).toEqual([]);
    });

    it('should handle errors when reading directory', async () => {
      // 模拟readdir方法失败
      mockedFs.readdir.mockRejectedValue(new Error('Failed to read directory'));
      
      const result = await noteManager.searchNotes('query');
      
      expect(result).toEqual([]);
    });
  });
});
