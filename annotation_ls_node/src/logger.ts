import {
    Connection,
    LogMessageNotification,
    MessageType,
    RemoteConsole
} from 'vscode-languageserver';

/**
 * 日志管理器类
 */
export class Logger {
    private connection: Connection | null;
    private console: RemoteConsole;
    private debugMode: boolean;

    /**
     * 构造函数
     * @param consoleOrConnection 控制台对象或LSP连接
     * @param console 控制台对象（当第一个参数是Connection时使用）
     * @param debugMode 是否启用调试模式
     */
    constructor(consoleOrConnection: RemoteConsole | Connection, console?: RemoteConsole, debugMode: boolean = false) {
        if ((consoleOrConnection as RemoteConsole).error && (consoleOrConnection as RemoteConsole).info) {
            // 传入的是RemoteConsole
            this.connection = null;
            this.console = consoleOrConnection as RemoteConsole;
        } else {
            // 传入的是Connection
            this.connection = consoleOrConnection as Connection;
            this.console = console!;
        }
        this.debugMode = debugMode;
    }

    /**
     * 设置调试模式
     * @param enabled 是否启用
     */
    setDebugMode(enabled: boolean): void {
        this.debugMode = enabled;
    }

    /**
     * 记录错误信息
     * @param message 错误消息
     */
    error(message: string): void {
        if (this.connection) {
            this.connection.sendNotification(
                LogMessageNotification.type,
                {
                    type: MessageType.Error,
                    message: `[ERROR] ${message}`
                }
            );
        }
        this.console.error(`[ERROR] ${message}`);
    }

    /**
     * 记录警告信息
     * @param message 警告消息
     */
    warn(message: string): void {
        if (this.connection) {
            this.connection.sendNotification(
                LogMessageNotification.type,
                {
                    type: MessageType.Warning,
                    message: `[WARN] ${message}`
                }
            );
        }
        this.console.warn(`[WARN] ${message}`);
    }

    /**
     * 记录信息
     * @param message 信息消息
     */
    info(message: string): void {
        if (this.connection) {
            this.connection.sendNotification(
                LogMessageNotification.type,
                {
                    type: MessageType.Info,
                    message: `[INFO] ${message}`
                }
            );
        }
        this.console.info(`[INFO] ${message}`);
    }

    /**
     * 记录调试信息（仅在调试模式下）
     * @param message 调试消息
     */
    debug(message: string): void {
        if (this.debugMode) {
            if (this.connection) {
                this.connection.sendNotification(
                    LogMessageNotification.type,
                    {
                        type: MessageType.Log,
                        message: `[DEBUG] ${message}`
                    }
                );
            }
            this.console.log(`[DEBUG] ${message}`);
        }
    }

    /**
     * 记录日志信息
     * @param message 日志消息
     */
    log(message: string): void {
        if (this.connection) {
            this.connection.sendNotification(
                LogMessageNotification.type,
                {
                    type: MessageType.Log,
                    message: message
                }
            );
        }
        this.console.log(message);
    }
}
