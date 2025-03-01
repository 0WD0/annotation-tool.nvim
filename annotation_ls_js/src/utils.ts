import { Position, Range } from 'vscode-languageserver';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { Config } from './config';

/**
 * 查找文档中的标注
 * @param document 文档
 * @param position 位置
 * @param config 配置
 */
export function findAnnotationRange(
    document: TextDocument,
    position: Position,
    config: Config
): { id: number, range: Range } | null {
    const text = document.getText();
    const offset = document.offsetAt(position);
    
    // 创建正则表达式来匹配标注
    // 例如，对于 「1」 格式，正则表达式是 /「(\d+)」/g
    const pattern = new RegExp(`${escapeRegExp(config.leftBracket)}(\\d+)${escapeRegExp(config.rightBracket)}`, 'g');
    
    let match;
    while ((match = pattern.exec(text)) !== null) {
        const startOffset = match.index;
        const endOffset = startOffset + match[0].length;
        
        // 检查光标是否在标注范围内
        if (offset >= startOffset && offset <= endOffset) {
            const id = parseInt(match[1], 10);
            const range = {
                start: document.positionAt(startOffset),
                end: document.positionAt(endOffset)
            };
            
            return { id, range };
        }
    }
    
    return null;
}

/**
 * 获取文档中的所有标注
 * @param document 文档
 * @param config 配置
 */
export function getAllAnnotations(
    document: TextDocument,
    config: Config
): Array<{ id: number, range: Range }> {
    const text = document.getText();
    const annotations: Array<{ id: number, range: Range }> = [];
    
    // 创建正则表达式来匹配标注
    // 例如，对于 「1」 格式，正则表达式是 /「(\d+)」/g
    const pattern = new RegExp(`${escapeRegExp(config.leftBracket)}(\\d+)${escapeRegExp(config.rightBracket)}`, 'g');
    
    let match;
    while ((match = pattern.exec(text)) !== null) {
        const startOffset = match.index;
        const endOffset = startOffset + match[0].length;
        const id = parseInt(match[1], 10);
        
        const range = {
            start: document.positionAt(startOffset),
            end: document.positionAt(endOffset)
        };
        
        annotations.push({ id, range });
    }
    
    return annotations;
}

/**
 * 生成唯一的标注ID
 * @param document 文档
 * @param config 配置
 */
export function generateUniqueAnnotationId(
    document: TextDocument,
    config: Config
): number {
    // 获取文档中的所有标注
    const annotations = getAllAnnotations(document, config);
    
    if (annotations.length === 0) {
        return 1;
    }
    
    // 找到最大ID并加1
    const maxId = Math.max(...annotations.map(a => a.id));
    return maxId + 1;
}

/**
 * 获取选中的文本
 * @param document 文档
 * @param range 范围
 */
export function getSelectedText(
    document: TextDocument,
    range: Range
): string {
    const startOffset = document.offsetAt(range.start);
    const endOffset = document.offsetAt(range.end);
    
    return document.getText().substring(startOffset, endOffset);
}

/**
 * 创建标注文本
 * @param selectedText 选中的文本
 * @param id 标注ID
 * @param config 配置
 */
export function createAnnotationText(
    selectedText: string,
    id: number,
    config: Config
): string {
    return `${config.leftBracket}${id}${config.rightBracket}${selectedText}`;
}

/**
 * 转义正则表达式中的特殊字符
 * @param string 需要转义的字符串
 */
function escapeRegExp(string: string): string {
    return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); // $& 表示整个匹配的字符串
}

/**
 * 查找文本中的所有标注范围
 * @param text 文本内容
 * @param leftBracket 左括号
 * @param rightBracket 右括号
 */
export function findAnnotationRanges(
    text: string,
    leftBracket: string,
    rightBracket: string
): Array<{ id: number, start: { line: number, character: number }, end: { line: number, character: number } }> {
    console.log(`Finding annotation ranges with brackets: "${leftBracket}", "${rightBracket}"`);
    console.log(`Text length: ${text.length}`);
    
    const ranges: Array<{ id: number, start: { line: number, character: number }, end: { line: number, character: number } }> = [];
    
    // 转义特殊字符
    const escapedLeftBracket = escapeRegExp(leftBracket);
    const escapedRightBracket = escapeRegExp(rightBracket);
    
    console.log(`Escaped brackets: "${escapedLeftBracket}", "${escapedRightBracket}"`);
    
    // 创建正则表达式来匹配完整的标注（包括开始和结束标记）
    // 例如，对于 「1」text「1」 格式，正则表达式是 /「(\d+)」(.*?)「\1」/gs
    const pattern = new RegExp(`${escapedLeftBracket}(\\d+)${escapedRightBracket}(.*?)${escapedLeftBracket}\\1${escapedRightBracket}`, 'gs');
    console.log(`Regex pattern: ${pattern.toString()}`);
    
    // 将文本拆分为行，以便计算行号和字符位置
    const lines = text.split('\n');
    console.log(`Text has ${lines.length} lines`);
    
    // 创建一个函数，将文本偏移量转换为行号和字符位置
    const offsetToPosition = (offset: number): { line: number, character: number } => {
        let line = 0;
        let character = offset;
        
        for (let i = 0; i < lines.length; i++) {
            if (character <= lines[i].length) {
                line = i;
                break;
            }
            
            // 减去当前行的长度和换行符（1个字符）
            character -= lines[i].length + 1;
        }
        
        return { line, character };
    };
    
    // 查找所有匹配项
    let match;
    let matchCount = 0;
    
    while ((match = pattern.exec(text)) !== null) {
        matchCount++;
        console.log(`Match #${matchCount}: ${JSON.stringify(match)}`);
        
        const id = parseInt(match[1], 10);
        if (isNaN(id)) {
            console.log(`Skipping invalid ID: ${match[1]}`);
            continue; // 跳过无效的ID
        }
        
        const startOffset = match.index;
        const endOffset = startOffset + match[0].length;
        
        console.log(`Match found at offsets: ${startOffset}-${endOffset}`);
        console.log(`Full match: "${match[0]}"`);
        console.log(`ID: ${id}, Content: "${match[2]}"`);
        
        const startPos = offsetToPosition(startOffset);
        const endPos = offsetToPosition(endOffset);
        
        console.log(`Positions: Start(${startPos.line},${startPos.character}), End(${endPos.line},${endPos.character})`);
        
        ranges.push({
            id,
            start: startPos,
            end: endPos
        });
    }
    
    console.log(`Found ${ranges.length} annotation ranges`);
    return ranges;
}

/**
 * 从文本中提取指定范围的内容
 * @param text 文本内容
 * @param range 范围
 */
export function extractTextFromRange(
    text: string,
    range: { start: { line: number, character: number }, end: { line: number, character: number } }
): string {
    console.log(`Extracting text from range: ${JSON.stringify(range)}`);
    
    // 将文本拆分为行
    const lines = text.split('\n');
    console.log(`Text has ${lines.length} lines`);
    
    // 如果是单行范围
    if (range.start.line === range.end.line) {
        console.log(`Single line range: line ${range.start.line}`);
        
        if (range.start.line >= lines.length) {
            console.error(`Start line ${range.start.line} is out of bounds (max: ${lines.length - 1})`);
            return '';
        }
        
        const line = lines[range.start.line];
        console.log(`Line content: "${line}"`);
        console.log(`Extracting from character ${range.start.character} to ${range.end.character}`);
        
        if (range.start.character > line.length) {
            console.error(`Start character ${range.start.character} is out of bounds (line length: ${line.length})`);
            return '';
        }
        
        const result = line.substring(range.start.character, range.end.character);
        console.log(`Extracted text: "${result}"`);
        return result;
    }
    
    // 如果是多行范围
    console.log(`Multi-line range: from line ${range.start.line} to ${range.end.line}`);
    let result = '';
    
    // 第一行
    if (range.start.line < lines.length) {
        const firstLine = lines[range.start.line];
        console.log(`First line content: "${firstLine}"`);
        
        if (range.start.character <= firstLine.length) {
            result += firstLine.substring(range.start.character) + '\n';
            console.log(`Added first line: "${firstLine.substring(range.start.character)}"`);
        } else {
            console.error(`Start character ${range.start.character} is out of bounds for first line (length: ${firstLine.length})`);
        }
    } else {
        console.error(`Start line ${range.start.line} is out of bounds (max: ${lines.length - 1})`);
        return '';
    }
    
    // 中间行
    for (let i = range.start.line + 1; i < range.end.line && i < lines.length; i++) {
        result += lines[i] + '\n';
        console.log(`Added middle line ${i}: "${lines[i]}"`);
    }
    
    // 最后一行
    if (range.end.line < lines.length) {
        const lastLine = lines[range.end.line];
        console.log(`Last line content: "${lastLine}"`);
        
        if (range.end.character <= lastLine.length) {
            result += lastLine.substring(0, range.end.character);
            console.log(`Added last line: "${lastLine.substring(0, range.end.character)}"`);
        } else {
            console.error(`End character ${range.end.character} is out of bounds for last line (length: ${lastLine.length})`);
            result += lastLine;
            console.log(`Added entire last line: "${lastLine}"`);
        }
    } else if (range.end.line === lines.length && range.end.character === 0) {
        // This is a valid case where the range ends at the very end of the file
        console.log(`Range ends at the end of the file`);
    } else {
        console.error(`End line ${range.end.line} is out of bounds (max: ${lines.length - 1})`);
    }
    
    console.log(`Final extracted text: "${result}"`);
    return result;
}
