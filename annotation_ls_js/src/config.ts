/**
 * 标注工具配置
 */
export class Config {
    // 默认左括号
    static readonly DEFAULT_LEFT_BRACKET = '「';
    
    // 默认右括号
    static readonly DEFAULT_RIGHT_BRACKET = '」';
    
    // 左括号
    private _leftBracket: string;
    
    // 右括号
    private _rightBracket: string;
    
    constructor(leftBracket?: string, rightBracket?: string) {
        this._leftBracket = leftBracket || Config.DEFAULT_LEFT_BRACKET;
        this._rightBracket = rightBracket || Config.DEFAULT_RIGHT_BRACKET;
    }
    
    /**
     * 获取左括号
     */
    get leftBracket(): string {
        return this._leftBracket;
    }
    
    /**
     * 设置左括号
     */
    set leftBracket(value: string) {
        this._leftBracket = value;
    }
    
    /**
     * 获取右括号
     */
    get rightBracket(): string {
        return this._rightBracket;
    }
    
    /**
     * 设置右括号
     */
    set rightBracket(value: string) {
        this._rightBracket = value;
    }
}
