#!/usr/bin/env python3

from lsprotocol import types

class Logger:
	def __init__(self):
		self._server = None
		self.debug = True

	def set_server(self, server):
		self._server = server

	def error(self, msg: str) -> None:
		if self._server:
			self._server.show_message(msg, types.MessageType.Error)

	def info(self, msg: str) -> None:
		if self._server and self.debug:
			self._server.show_message(msg, types.MessageType.Info)

logger = Logger()

def error(msg: str = "") -> None:
	logger.error(msg)

def info(msg: str = "") -> None:
	logger.info(msg)
