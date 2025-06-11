#!/usr/bin/env python3

from lsprotocol import types


class Logger:
	def __init__(self):
		"""
		初始化 Logger 实例，将 _server 属性设为 None，debug 标志设为 True。
		"""
		self._server = None
		self.debug = True

	def set_server(self, server):
		self._server = server

	def error(self, msg: str) -> None:
		if self._server:
			self._server.show_message(msg, types.MessageType.Error)

	def info(self, msg: str) -> None:
		"""
		向服务器发送信息级别的日志消息，仅在调试模式下生效。

		如果已设置服务器且调试模式开启，则通过服务器接口显示信息消息。
		"""
		if self._server and self.debug:
			self._server.show_message(msg, types.MessageType.Info)


logger = Logger()


def error(msg: str = "") -> None:
	"""
	发送错误日志消息到全局 Logger 实例。

	Args:
		msg: 要记录的错误信息。
	"""
	logger.error(msg)


def info(msg: str = "") -> None:
	"""
	向服务器发送信息级别的日志消息。

	如果 Logger 实例已设置服务器且调试模式开启，则将消息作为信息类型发送到服务器。
	"""
	logger.info(msg)
