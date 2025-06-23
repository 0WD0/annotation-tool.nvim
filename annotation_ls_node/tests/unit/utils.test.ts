import { 
  findAnnotationRanges, 
  extractTextFromRange, 
  createAnnotationText 
} from '../../src/utils';
import { Config } from '../../src/config';

// 禁用控制台输出，减少测试输出噪音
jest.spyOn(console, 'log').mockImplementation(() => {});

describe('Utils Functions', () => {
  describe('findAnnotationRanges', () => {
    it('should find annotation ranges with Japanese brackets', () => {
      const text = '这是一段测试文本。「1」这是第一个标注「1」继续一些文本。「2」这是第二个标注「2」结束。';
      const leftBracket = '「';
      const rightBracket = '」';
      
      const ranges = findAnnotationRanges(text, leftBracket, rightBracket);
      
      expect(ranges).toHaveLength(2);
      expect(ranges[0].id).toBe(1);
      expect(ranges[1].id).toBe(2);
    });

    it('should handle multiline annotations', () => {
      const text = '这是一段测试文本。\n「1」这是第一个\n多行标注「1」\n继续一些文本。';
      const leftBracket = '「';
      const rightBracket = '」';
      
      const ranges = findAnnotationRanges(text, leftBracket, rightBracket);
      
      expect(ranges).toHaveLength(1);
      expect(ranges[0].id).toBe(1);
      expect(ranges[0].start.line).toBe(1);
      expect(ranges[0].end.line).toBe(2);
    });

    it('should return empty array when no annotations are found', () => {
      const text = '这是一段没有标注的测试文本。';
      const leftBracket = '「';
      const rightBracket = '」';
      
      const ranges = findAnnotationRanges(text, leftBracket, rightBracket);
      
      expect(ranges).toHaveLength(0);
    });
  });

  describe('extractTextFromRange', () => {
    it('should extract text from a single line range', () => {
      const text = '这是一行文本，包含一个标注。';
      const range = {
        start: { line: 0, character: 10 },
        end: { line: 0, character: 14 }
      };
      
      const result = extractTextFromRange(text, range);
      
      expect(result).toBe('包含一个');
    });

    it('should extract text from a multiline range', () => {
      const text = '第一行\n第二行\n第三行';
      const range = {
        start: { line: 0, character: 2 },
        end: { line: 2, character: 2 }
      };
      
      const result = extractTextFromRange(text, range);
      
      expect(result).toBe('一行\n第二行\n第');
    });

    it('should handle edge cases with out-of-bounds ranges', () => {
      const text = '单行文本';
      const range = {
        start: { line: 0, character: 2 },
        end: { line: 1, character: 2 }
      };
      
      const result = extractTextFromRange(text, range);
      
      expect(result).toBe('行文本');
    });
  });

  describe('createAnnotationText', () => {
    it('should create annotation text with the given ID and config', () => {
      const selectedText = '这是被选中的文本';
      const id = 42;
      const config = new Config('「', '」');
      
      const result = createAnnotationText(selectedText, id, config);
      
      expect(result).toBe('「42」这是被选中的文本「42」');
    });
  });
});
