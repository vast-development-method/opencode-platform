#!/usr/bin/env python3
"""Disposable TLS MCP fixture; verifies the real curl client's wire contract."""
import http.server
import json
import pathlib
import ssl
import sys

root = pathlib.Path(sys.argv[1])
tools = ['joomla_sites_list', 'joomla_capabilities', 'joomla_content_articles_list',
         'joomla_job_status', 'joomla_write_apply']

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, status, body=b'', headers=None):
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_DELETE(self):
        self.respond(204)

    def do_POST(self):
        if self.headers.get('X-Joomla-Token') != 'fixture-token':
            self.respond(401)
            return
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with (root / 'requests.jsonl').open('a') as stream:
            stream.write(json.dumps({'method': data['method'], 'params': data.get('params', {})}) + '\n')
        method = data['method']
        if '/redirect/' in self.path:
            self.respond(302, headers={'Location': '/untrusted/api/index.php/v1/joomengine-mcp'})
            return
        if method != 'initialize' and (self.headers.get('Mcp-Session-Id') != 'fixture-session'
                or self.headers.get('MCP-Protocol-Version') != '2025-06-18'):
            self.respond(400)
            return
        if method == 'notifications/initialized':
            self.respond(202)
            return
        headers = {'Content-Type': 'application/json'}
        if method == 'initialize':
            headers['Mcp-Session-Id'] = 'fixture-session'
            result = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}},
                      'serverInfo': {'name': 'test-fixture', 'version': '1'}}
        elif method == 'tools/list':
            cursor = data.get('params', {}).get('cursor')
            names = tools[:2] if cursor is None else tools[2:]
            result = {'tools': [{'name': name, 'inputSchema': {'type': 'object'}} for name in names]}
            if cursor is None or '/loop/' in self.path:
                result['nextCursor'] = 'second-page'
            if cursor:
                headers['Content-Type'] = 'text/event-stream'
        elif method == 'tools/call':
            name = data['params']['name']
            if name not in tools:
                self.respond(400)
                return
            if name == 'joomla_write_apply':
                result = {'isError': True, 'content': [{'type': 'text', 'text': 'Execution uncertain; reconcile job fixture-1.'}]}
            elif name == 'joomla_job_status':
                result = {'isError': False, 'structuredContent': {'jobId': data['params']['arguments']['jobId'], 'status': 'completed'}, 'content': []}
            else:
                result = {'isError': False, 'structuredContent': {'items': []}, 'content': []}
        else:
            self.respond(400)
            return
        body = json.dumps({'jsonrpc': '2.0', 'id': data['id'], 'result': result}).encode()
        if headers['Content-Type'] == 'text/event-stream':
            body = b': keepalive\n\nevent: message\ndata: ' + body + b'\n\n'
        self.respond(200, body, headers)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root / 'cert.pem', root / 'key.pem')
server.socket = context.wrap_socket(server.socket, server_side=True)
(root / 'port').write_text(str(server.server_address[1]))
server.serve_forever()
