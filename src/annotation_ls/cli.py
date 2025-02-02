import argparse
import os
import sys
import subprocess
from typing import List, Optional, Dict, Any
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
		'--implementation',
		choices=['python', 'node'],
		default='python',
		help='Choose which implementation to use (default: python)'
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

	if args.implementation == 'python':
		py_server.start_server(args.connection, args.host, args.port)
	else:
		# 获取项目根目录
		project_root = os.path.abspath(os.path.join(
			os.path.dirname(__file__),
			'..',
			'..'
		))

		# 获取 Node.js 服务器路径
		server_path = os.path.join(
			project_root,
			'src',
			'annotation_ls_js',
			'out',
			'server.js'
		)

		# 检查编译后的文件是否存在
		if not os.path.exists(server_path):
			# 编译 TypeScript
			subprocess.run(
				['npm', 'run', 'compile'],
				cwd=project_root,
				check=True
			)

		# 设置环境变量
		env = os.environ.copy()
		if args.connection == 'tcp':
			env['CONNECTION_TYPE'] = 'tcp'
			env['HOST'] = args.host
			env['PORT'] = str(args.port)

		# 启动 Node.js 服务器
		cmd = ['node', server_path]
		if args.connection == 'stdio':
			cmd.append('--stdio')

		subprocess.run(
			cmd,
			env=env,
			check=True
		)

	return 0

if __name__ == '__main__':
	sys.exit(main())
