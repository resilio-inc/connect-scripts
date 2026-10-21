import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8446
TOKEN = sys.argv[2] if len(sys.argv) > 2 else 'test-token'
TOTAL = 25000
COLUMNS = ['SeqId', 'Timestamp', 'SeverityText', 'AgentId', 'JobId', 'Message']


def make_row(view, seq):
    return [seq, int(time.time() * 1000) - (TOTAL - seq) * 1000, 'info', f'agent-{seq % 5}', f'job-{seq % 3}',
            f'{view} synthetic row {seq}']


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/api/v2/analytics/query':
            return self._reply(404, {'error': 'not found'})
        auth = self.headers.get('Authorization', '')
        is_jwt = auth.startswith('Bearer ') and auth.count('.') == 2
        if auth != f'Token {TOKEN}' and not is_jwt:
            return self._reply(401, {'error': 'unauthorized'})

        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        sql = body['query']
        view = re.search(r'FROM (\w+)', sql).group(1)
        from_seq = int(re.search(r'"SeqId" > (\d+)', sql).group(1))
        limit = int(re.search(r'LIMIT (\d+)', sql).group(1))
        rows = [make_row(view, s) for s in range(from_seq + 1, min(from_seq + limit, TOTAL) + 1)]
        self._reply(200, {'meta': [{'name': c} for c in COLUMNS], 'rows': rows})

    def _reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
