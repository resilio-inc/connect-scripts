import json
import os
import sys
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

import requests
import urllib3

DEFAULT_VIEWS = ['audit_logs_view', 'events_logs_view', 'file_events_view']
SEVERITY_VIEWS = {'events_logs_view', 'file_events_view'}
OAUTH_TOKEN_REFRESH_MARGIN_SECONDS = 60
MAX_BATCHES_PER_RUN = 50

SCHEME = """<scheme>
  <title>Resilio Reporting</title>
  <description>Pulls Audit, Events and File Events from the Resilio Connect reporting API</description>
  <use_external_validation>false</use_external_validation>
  <use_single_instance>false</use_single_instance>
  <streaming_mode>xml</streaming_mode>
  <endpoint>
    <args>
      <arg name="base_url"><title>Base URL</title><required_on_create>true</required_on_create></arg>
      <arg name="api_token"><title>API token</title><required_on_create>false</required_on_create></arg>
      <arg name="oauth_token_url"><title>OAuth token URL</title><required_on_create>false</required_on_create></arg>
      <arg name="client_id"><title>OAuth client id</title><required_on_create>false</required_on_create></arg>
      <arg name="client_secret"><title>OAuth client secret</title><required_on_create>false</required_on_create></arg>
      <arg name="scope"><title>OAuth scope</title><required_on_create>false</required_on_create></arg>
      <arg name="views"><title>Views</title><required_on_create>false</required_on_create></arg>
      <arg name="query_limit"><title>Query limit</title><required_on_create>false</required_on_create></arg>
      <arg name="tls_verify"><title>TLS verify</title><required_on_create>false</required_on_create></arg>
      <arg name="ca_cert"><title>CA certificate path</title><required_on_create>false</required_on_create></arg>
    </args>
  </endpoint>
</scheme>"""


def log(level, message):
    print(f'{level} {message}', file=sys.stderr, flush=True)


def read_config():
    root = ET.fromstring(sys.stdin.read())
    checkpoint_dir = root.findtext('checkpoint_dir')
    stanzas = []
    for stanza in root.iter('stanza'):
        params = {p.get('name'): (p.text or '') for p in stanza.iter('param')}
        stanzas.append((stanza.get('name'), params))
    return checkpoint_dir, stanzas


def checkpoint_path(checkpoint_dir, stanza_name, key):
    safe = ''.join(c if c.isalnum() else '_' for c in stanza_name)
    return os.path.join(checkpoint_dir, f'{safe}__{key}')


def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def write_file(path, value):
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        f.write(value)
    os.replace(tmp, path)


def get_oauth_token(params, verify, cache_path):
    cached_raw = read_file(cache_path)
    if cached_raw:
        try:
            cached = json.loads(cached_raw)
            if cached.get('expires_at', 0) > time.time() + OAUTH_TOKEN_REFRESH_MARGIN_SECONDS:
                return cached['access_token']
        except (ValueError, KeyError):
            pass

    body = {
        'grant_type': 'client_credentials',
        'client_id': params['client_id'],
        'client_secret': params['client_secret'],
    }
    if params.get('scope'):
        body['scope'] = params['scope']

    resp = requests.post(params['oauth_token_url'], data=body, verify=verify, timeout=30)
    resp.raise_for_status()
    payload = resp.json()
    access_token = payload.get('access_token')
    if not access_token:
        raise ValueError('oauth token response missing access_token')

    write_file(cache_path, json.dumps({
        'access_token': access_token,
        'expires_at': time.time() + payload.get('expires_in', 3600),
    }))
    return access_token


def query_view(base_url, headers, view, from_seq, limit, verify):
    sql = (
        f'SELECT * FROM {view} '
        f'WHERE "SeqId" > {from_seq} '
        f'ORDER BY "SeqId" ASC '
        f'LIMIT {limit}'
    )
    resp = requests.post(f'{base_url}/api/v2/analytics/query', headers=headers,
                         json={'query': sql, 'limit': limit}, verify=verify, timeout=60)
    resp.raise_for_status()
    payload = resp.json()
    columns = [c['name'] for c in payload.get('meta', [])]
    return [dict(zip(columns, row)) for row in payload.get('rows', [])]


def write_events(stanza_name, view, records):
    out = ['<stream>']
    for record in records:
        ts_ms = record.get('Timestamp')
        ts = ts_ms / 1000.0 if ts_ms else time.time()
        data = json.dumps(record, default=str)
        out.append(
            f'<event stanza="{escape(stanza_name)}"><time>{ts:.3f}</time>'
            f'<sourcetype>resilio:{view}</sourcetype>'
            f'<data>{escape(data)}</data></event>')
    out.append('</stream>')
    sys.stdout.write('\n'.join(out) + '\n')
    sys.stdout.flush()


def collect_stanza(checkpoint_dir, stanza_name, params):
    base_url = params.get('base_url', '').rstrip('/')
    if not base_url:
        raise ValueError('base_url is required')

    tls_verify = params.get('tls_verify', 'true').strip().lower() not in ('false', '0', 'no')
    verify = params.get('ca_cert') or tls_verify
    if verify is False:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    views = [v.strip() for v in params.get('views', '').split(',') if v.strip()] or DEFAULT_VIEWS
    limit = int(params.get('query_limit') or 10000)

    if params.get('oauth_token_url') and params.get('client_id') and params.get('client_secret'):
        token = get_oauth_token(params, verify, checkpoint_path(checkpoint_dir, stanza_name, 'oauth_token'))
        headers = {'Authorization': f'Bearer {token}'}
    elif params.get('api_token'):
        headers = {'Authorization': f'Token {params["api_token"]}'}
    else:
        raise ValueError('api_token or oauth_token_url/client_id/client_secret are required')

    for view in views:
        cursor_path = checkpoint_path(checkpoint_dir, stanza_name, f'cursor_{view}')
        raw = read_file(cursor_path)
        last_seq = int(raw) if raw and raw.isdigit() else 0

        try:
            for _ in range(MAX_BATCHES_PER_RUN):
                records = query_view(base_url, headers, view, last_seq, limit, verify)
                if not records:
                    break
                write_events(stanza_name, view, records)
                last_seq = max(last_seq, max(r.get('SeqId') or 0 for r in records))
                write_file(cursor_path, str(last_seq))
                if len(records) < limit:
                    break
        except (requests.RequestException, ValueError) as e:
            log('ERROR', f'resilio_reporting {stanza_name} view={view}: {e}')


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--scheme':
        print(SCHEME)
        return
    if len(sys.argv) > 1 and sys.argv[1] == '--validate-arguments':
        return

    checkpoint_dir, stanzas = read_config()
    for stanza_name, params in stanzas:
        try:
            collect_stanza(checkpoint_dir, stanza_name, params)
        except (requests.RequestException, ValueError) as e:
            log('ERROR', f'resilio_reporting {stanza_name}: {e}')


if __name__ == '__main__':
    main()
