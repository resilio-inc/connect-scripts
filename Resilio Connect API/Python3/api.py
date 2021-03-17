from enum import Enum
from functools import wraps
from json import JSONDecodeError
import requests

from errors import ApiConnectionError, ApiUnauthorizedError, ApiError
from logger import logger

BASE_API_URL = '/api/v2'


def authorized_api_request(func):
    @wraps(func)
    def wrapper(self, url, *args, **kwargs):
        kwargs['headers'] = {
            'Authorization': 'Token {}'.format(self._token),
            'Content-Type': 'application/json'
        }
        kwargs['verify'] = self._verify

        url = self._base_url + url

        try:
            response = func(self, url, *args, **kwargs)
        except requests.RequestException as e:
            raise ApiConnectionError('Connection to Management Console failed', e)

        if response.status_code >= 400:
            try:
                message = response.json().get('message', '')
            except JSONDecodeError:
                message = response.text

            if response.status_code == 401:
                raise ApiUnauthorizedError(message)

            raise ApiError(message)

        return response
    return wrapper


class ApiBaseCommands:
    def __init__(self, address, token, verify):
        self._token = token
        self._address = address
        self._base_url = address + BASE_API_URL
        self._verify = verify

    # Request methods
    @authorized_api_request
    def _get(self, *args, **kwargs):
        return requests.get(*args, **kwargs)

    @authorized_api_request
    def _post(self, *args, **kwargs):
        return requests.post(*args, **kwargs)

    @authorized_api_request
    def _put(self, *args, **kwargs):
        return requests.put(*args, **kwargs)

    @authorized_api_request
    def _delete(self, *args, **kwargs):
        return requests.delete(*args, **kwargs)

    # Helpers
    def _create(self, *args, **kwargs):
        r = self._post(*args, **kwargs)
        try:
            return r.json()['id']
        except JSONDecodeError as e:
            raise ApiError('Response is not a json: {}. {}'.format(r.text, e))

    def _get_json(self, *args, **kwargs):
        r = self._get(*args, **kwargs)
        try:
            return r.json()
        except JSONDecodeError as e:
            raise ApiError('Response is not a json: {}. {}'.format(r.text, e))

    # Agents
    def _get_agents(self):
        # https://connect-download-2-12-pr.resilio.com/#api-Agents-GetAgents
        return self._get_json('/agents')

    def _get_agent(self, agent_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Agents-GetAgent
        return self._get_json('/agents/{}'.format(agent_id))

    def _update_agent(self, agent_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Agents-UpdateAgent
        self._put('/agents/{}'.format(agent_id), json=attrs)

    def _get_agent_config(self):
        # https://connect-download-2-12-pr.resilio.com/#api-Agents-GetAgentConfig
        return self._get_json('/agents/config')

    def _delete_agent(self, agent_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Agents-DeleteAgent
        self._delete('/agents/{}'.format(agent_id))

    # Groups
    def _get_groups(self):
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-GetGroups
        return self._get_json('/groups')

    def _get_group(self, group_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-GetGroup
        return self._get_json('/groups/{}'.format(group_id))

    def _create_group(self, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-CreateGroup
        return int(self._create('/groups', json=attrs))

    def _update_group(self, group_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-UpdateGroup
        self._put('/groups/{}'.format(group_id), json=attrs)

    def _delete_group(self, group_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-DeleteGroup
        self._delete('/groups/{}'.format(group_id))

    # Jobs
    def _get_jobs(self):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-GetJobs
        return self._get_json('/jobs')

    def _get_job(self, job_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-GetJob
        return self._get_json('/jobs/{}'.format(job_id))

    def _create_job(self, attrs, ignore_errors=False):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-CreateJob
        return int(self._create('/jobs', params={'ignore_errors': ignore_errors}, json=attrs))

    def _update_job(self, job_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-UpdateJob
        self._put('/jobs/{}'.format(job_id), json=attrs)

    def _delete_job(self, job_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-DeleteJob
        self._delete('/jobs/{}'.format(job_id))

    def _get_job_groups(self, job_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-JobGroups
        return self._get_json('/jobs/{}/groups'.format(job_id))

    # Job Runs
    def _get_job_run(self, job_run_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-GetRun
        return self._get_json('/runs/{}'.format(job_run_id))

    def _get_job_runs(self, attrs=None):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-GetRuns
        return self._get_json('/runs', params=attrs)

    def _create_job_run(self, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-CreateRun
        return int(self._create('/runs', json=attrs))

    def _stop_job_run(self, job_run_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-StopRun
        self._put('/runs/{}/stop'.format(job_run_id))

    def _get_job_run_agent(self, job_run_id, agent_id):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-RunAgent
        return self._get_json('/runs/{}/agents/{}'.format(job_run_id, agent_id))

    def _get_job_run_agents(self, job_run_id, attrs=None):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-RunAgents
        return self._get_json('/runs/{}/agents'.format(job_run_id), params=attrs)

    def _add_agent_to_job_run(self, job_run_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-AddAgentsToRun
        self._post('/runs/{}/agents'.format(job_run_id), json=attrs)

    def _stop_run_on_agents(self, job_run_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-StopRunOnAgents
        self._put('/runs/{}/agents/stop'.format(job_run_id), json=attrs)

    def _restart_agent_in_active_job_run(self, job_run_id, attrs):
        # https://connect-download-2-12-pr.resilio.com/#api-Runs-RestartAgentsInRun
        self._put('/runs/{}/agents/restart'.format(job_run_id), json=attrs)
