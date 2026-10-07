import json
import re
import time

import requests
from datadog_checks.base import AgentCheck

DEFAULT_VIEWS = ['audit_logs_view', 'events_logs_view', 'file_events_view']
SEVERITY_VIEWS = {'events_logs_view', 'file_events_view'}

TAG_COLUMNS = ('AgentId', 'AgentPeerId', 'JobId', 'JobRunId')

_CAMEL_RE = re.compile(r'(?<!^)(?=[A-Z])')

OAUTH_TOKEN_REFRESH_MARGIN_SECONDS = 60


def _snake_case(name):
    return _CAMEL_RE.sub('_', name).lower()


class ResilioReportingCheck(AgentCheck):
    def check(self, instance):
        base_url = instance.get('base_url')
        api_token = instance.get('api_token')
        oauth_token_url = instance.get('oauth_token_url')
        client_id = instance.get('client_id')
        client_secret = instance.get('client_secret')
        views = instance.get('views', DEFAULT_VIEWS)
        query_limit = instance.get('query_limit', 5000)
        tls_verify = instance.get('tls_verify', True)
        ca_cert = instance.get('ca_cert')
        verify = ca_cert if ca_cert else tls_verify
        extra_tags = instance.get('tags', [])

        if not base_url:
            self.service_check('resilio_reporting.can_connect', AgentCheck.CRITICAL,
                                message='base_url is required', tags=extra_tags)
            return

        if oauth_token_url and client_id and client_secret:
            access_token = self._get_oauth_token(
                oauth_token_url, client_id, client_secret, instance.get('scope'), verify, extra_tags)
            if access_token is None:
                return
            headers = {'Authorization': f'Bearer {access_token}'}
        elif api_token:
            headers = {'Authorization': f'Token {api_token}'}
        else:
            self.service_check('resilio_reporting.can_connect', AgentCheck.CRITICAL,
                                message='api_token or oauth_token_url/client_id/client_secret are required',
                                tags=extra_tags)
            return

        for view in views:
            cursor_key = f'cursor_{view}'
            last_seq = self._read_cursor(cursor_key)
            if last_seq is None:
                last_seq = 0

            last_processed_seq = self._collect_view(
                base_url, headers, view, last_seq, verify, extra_tags, query_limit)

            if last_processed_seq is not None:
                self._write_cursor(cursor_key, last_processed_seq)

    def _get_oauth_token(self, token_url, client_id, client_secret, scope, verify, extra_tags):
        cached_raw = self.read_persistent_cache('oauth_token_cache')
        if cached_raw:
            try:
                cached = json.loads(cached_raw)
                if cached.get('expires_at', 0) > time.time() + OAUTH_TOKEN_REFRESH_MARGIN_SECONDS:
                    return cached['access_token']
            except (ValueError, KeyError):
                pass

        body = {'grant_type': 'client_credentials', 'client_id': client_id, 'client_secret': client_secret}
        if scope:
            body['scope'] = scope

        try:
            resp = requests.post(token_url, data=body, verify=verify, timeout=30)
            resp.raise_for_status()
        except requests.RequestException as e:
            self.service_check('resilio_reporting.can_connect', AgentCheck.CRITICAL,
                                message=f'oauth token request failed: {e}', tags=extra_tags)
            return None

        payload = resp.json()
        access_token = payload.get('access_token')

        if not access_token:
            self.service_check('resilio_reporting.can_connect', AgentCheck.CRITICAL,
                                message='oauth token response missing access_token', tags=extra_tags)
            return None

        self.write_persistent_cache('oauth_token_cache', json.dumps({
            'access_token': access_token,
            'expires_at': time.time() + payload.get('expires_in', 3600),
        }))

        return access_token

    def _read_cursor(self, key):
        raw = self.read_persistent_cache(key)
        if not raw:
            return None
        try:
            return int(raw)
        except ValueError:
            return None

    def _write_cursor(self, key, value):
        self.write_persistent_cache(key, str(value))

    def _collect_view(self, base_url, headers, view, from_seq, verify, extra_tags, limit):
        url = f'{base_url}/api/v2/analytics/query'
        view_tags = extra_tags + [f'view:{view}']
        sql = (
            f'SELECT * FROM {view} '
            f'WHERE "SeqId" > {from_seq} '
            f'ORDER BY "SeqId" ASC '
            f'LIMIT {limit}'
        )
        body = {'query': sql, 'limit': limit}

        try:
            resp = requests.post(url, headers=headers, json=body, verify=verify, timeout=30)
            resp.raise_for_status()
        except requests.RequestException as e:
            self.service_check('resilio_reporting.can_connect', AgentCheck.CRITICAL, message=str(e), tags=view_tags)
            return None

        self.service_check('resilio_reporting.can_connect', AgentCheck.OK, tags=view_tags)
        payload = resp.json()
        columns = [c['name'] for c in payload.get('meta', [])]
        last_processed_seq = None

        for row in payload.get('rows', []):
            record = dict(zip(columns, row))
            self._emit_row_log(view, record, view_tags)
            seq = record.get('SeqId')
            if seq is not None:
                last_processed_seq = seq

        return last_processed_seq

    def _row_tags(self, record, base_tags):
        tags = list(base_tags)
        for col in TAG_COLUMNS:
            value = record.get(col)
            if value is not None:
                tags.append(f'{_snake_case(col)}:{value}')
        return tags

    def _emit_row_log(self, view, record, view_tags):
        tags = self._row_tags(record, view_tags)
        ts_ms = record.get('Timestamp')
        status = record.get('SeverityText', 'info') if view in SEVERITY_VIEWS else 'info'

        self.send_log({
            'message': json.dumps(record, default=str),
            'timestamp': ts_ms / 1000.0 if ts_ms else time.time(),
            'status': status,
            'ddtags': ','.join(tags),
        })
