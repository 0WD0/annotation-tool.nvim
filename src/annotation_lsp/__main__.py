#!/usr/bin/env python3
from .server import AnnotationServer

def main():
	server = AnnotationServer()
	server.start_io()

if __name__ == "__main__":
	main()
