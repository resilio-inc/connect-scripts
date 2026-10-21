[resilio_reporting://<name>]
base_url = Resilio Connect server URL, e.g. https://host:8446
api_token = API token (sent as "Authorization: Token <api_token>")
oauth_token_url = OAuth2 token endpoint (client_credentials); used instead of api_token when set together with client_id and client_secret
client_id = OAuth2 client id
client_secret = OAuth2 client secret
scope = OAuth2 scope (optional)
views = Comma-separated list of views. Default: audit_logs_view,events_logs_view,file_events_view
query_limit = Max rows per request. Default: 10000
tls_verify = true/false. Default: true
ca_cert = Path to a CA bundle used to verify the server certificate (optional)
