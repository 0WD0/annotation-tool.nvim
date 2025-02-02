import argparse
import sys
from typing import List, Optional
from . import server as py_server
from . import __version__

def main(argv: Optional[List[str]] = None) -> int:
	parser = argparse.ArgumentParser(
		description='Language Server for Annotation Tool'
	)
	parser.add_argument(
		'--version',
		action='version',
		version=f'%(prog)s {__version__}'
	)
	parser.add_argument(
		'--connection',
		choices=['stdio', 'tcp'],
		default='stdio',
		help='Connection type (default: stdio)'
	)
	parser.add_argument(
		'--host',
		default='127.0.0.1',
		help='Host for TCP connection (default: 127.0.0.1)'
	)
	parser.add_argument(
		'--port',
		type=int,
		default=2087,
		help='Port for TCP connection (default: 2087)'
	)
	args = parser.parse_args(argv)

	# 启动服务器
	py_server.start_server(args.connection, args.host, args.port)
	return 0

if __name__ == '__main__':
	sys.exit(main())
