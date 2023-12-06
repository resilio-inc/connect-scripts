import json
import time
from json import JSONDecodeError
import requests

from api import ApiBaseCommands
from errors import ApiError
from logger import logger


AGENT_API_PORT = 3840


class ConnectApiExample(ApiBaseCommands):
    def __init__(self, address, token, verify=False):
        super(ConnectApiExample, self).__init__(address, token, verify)

        if not verify:
            from requests.packages.urllib3.exceptions import InsecureRequestWarning
            requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    def get_agents(self):
        """
        Get list of all agents

        :return: tuple with dict items or None in case of error:
        {
            'id': '<agent_id>',
            'name': '<agent_name>',
            'ip': '<agent_ip>',
            'os': '<agent_os>'
        }
        """

        try:
            agents = self._get_agents()
        except ApiError as e:
            logger.error("Failed to fetch list of agents {}".format(e))
            return None
        else:
            logger.info("Successfully fetched list of agents")
            return tuple(
                {
                    'id': agent['id'],
                    'name': agent['name'],
                    'ip': agent['ip'],
                    'os': agent['os']
                } for agent in agents
            )

    def create_group(self, name, agents_ids, description=''):
        """
        Create group with agents

        :param name: Group name
        :param agents_ids: Agent IDs iterable object
        :param description: Group description
        :return: Group ID or None in case of error
        """

        attrs = {
            'name': name,
            'description': description,
            'agents': [
                {'id': agent_id} for agent_id in agents_ids
            ]
        }

        # all acceptable params for attr dict here:
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-CreateGroup

        try:
            group_id = self._create_group(attrs)
            logger.debug("Created group with ID {}".format(group_id))
        except ApiError as e:
            logger.error("Failed to create group: {}".format(e))
            return None
        else:
            logger.info("Successfully created group {}".format(attrs['name']))
            return group_id

    def delete_group(self, group_id):
        """
        Delete group by id

        :param group_id: Id of a group to be deleted
        :return: True if operation was successful, otherwise False
        """

        try:
            self._delete_group(group_id)
            logger.debug("Deleted group with id {}".format(group_id))
        except ApiError as e:
            logger.error("Failed to delete group {}".format(e))
            return False
        else:
            logger.info("Successfully deleted group {}".format(group_id))
            return True

    def add_agents_to_group(self, group_id, agents_ids):
        """
        Add new agents to existed group

        :param group_id: Group ID
        :param agents_ids: Agent IDs iterable object
        :return: True if operation was successful, otherwise False
        """

        attrs = {
            'agents': [
                {'id': agent_id} for agent_id in agents_ids
            ]
        }

        # all acceptable params for attr dict here:
        # https://connect-download-2-12-pr.resilio.com/#api-Groups-UpdateGroup

        try:
            self._update_group(group_id, attrs)
        except ApiError as e:
            logger.error("Failed to add agents to group {}, {}".format(group_id, e))
            return False
        else:
            logger.info("Successfully added agents to group {}".format(group_id))
            return True

    def get_group_agents(self, group_id):
        """
        Get list of group agents

        :param group_id: Group ID
        :return: tuple object with agents ids or None in case of error
        """

        try:
            response = self._get_group(group_id)
            agents_ids = tuple(d["id"] for d in response["agents"])
        except ApiError as e:
            logger.error("Failed to get group agents {}".format(e))
            return None
        else:
            logger.info("Successfully fetched group agents")
            return agents_ids

    def create_job(self, job_name, job_type, description=None, groups_data=None):
        """
        Create a job

        :param job_name: Job name
        :param job_type: Job type: "consolidation", "distribution", "script", "sync"
        :param description: Job description
        :param groups_data: iterable object with dict items:
            {
                'id': <group_id>,
                'path': {
                    'linux': '/path/on/linux',
                    'win': 'c:\path\on\windows',
                    'osx': '/tmp/test'
                },
                'permission': <group_permissions>
            }
        :return: Job ID or None in case of error
        """

        if description is None:
            description = ''

        if groups_data is None:
            groups_data = []

        attrs = {
            'name': job_name,
            'type': job_type,
            'description': description,
            'groups': list(groups_data)
        }

        # all acceptable params for attr dict here:
        # https://connect-download-2-12-pr.resilio.com/#api-Jobs-CreateJob

        try:
            job_id = self._create_job(attrs)
            logger.debug("Created job with ID {}".format(job_id))
        except ApiError as e:
            logger.error("Failed to create job {}".format(e))
            return None
        else:
            logger.info("Successfully created job")
            return job_id

    def create_job_run(self, job_id):
        """
        Create run for a job

        :param job_id: Job ID
        :return: Job Run ID or None in case of error
        """

        attrs = {
            "job_id": job_id
        }

        try:
            job_run_id = self._create_job_run(attrs)
            logger.debug("Created job run {}".format(job_run_id))
        except ApiError as e:
            logger.error("Failed to create job run {}".format(e))
            return None
        else:
            logger.info("Successfully created job run {}".format(job_run_id))
            return job_run_id

    def assign_jobs_to_group(self, group_id, jobs_data):
        """
        Assign existing jobs to existing group

        :param group_id: Group ID
        :param jobs_data: iterable object with dict items:
        {
            "id": <job_id>,
            "permission": <job_permissions>,
            "path": {
                "linux": "/path/on/linux",
                "win": "c:\path\on\windows",
                'osx': "/tmp/test"
            }
        }
        :return: True if operation was successful, otherwise False
        """

        attrs = {
            'jobs': list(jobs_data)
        }

        try:
            self._update_group(group_id, attrs)
        except ApiError as e:
            logger.error("Failed to assign jobs to group {}".format(e))
            return False
        else:
            logger.info("Successfully assigned jobs to group")
            return True

    def distribute_folder(self, job_name, job_desc, src_group_data, dst_groups_data):
        """
        Distribute folder from src to dst

        :param job_name: Job name
        :param job_desc: Job description
        :param src_group_data: src group data as dict:
        {
            'id': <group_id>,
            'path': {
                'linux': '/path/on/linux',
                'win': 'c:\path\on\windows',
                'osx': "/tmp/test"
            },
            'permission': <group_permissions>  # "ro", "rw", "sro", "srw"
        }
        :param dst_groups_data: iterable object with dict items:
        {
            'id': <group_id>,
            'path': {
                'linux': '/path/on/linux',
                'win': 'c:\path\on\windows',
                'osx': '/tmp/test'
            },
            'permission': <group_permissions>  # "ro", "rw", "sro", "srw"
        }
        :return: Job Run ID or None in case of error
        """

        groups_data = [src_group_data, ]
        groups_data.extend(dst_groups_data)

        # create job first
        job_id = self.create_job(job_name, "distribution", description=job_desc, groups_data=groups_data)

        if job_id is None:
            raise ApiError("Failed to create job {}".format(job_name))

        # start job by creating job run
        job_run_id = self.create_job_run(job_id)

        return job_run_id

    def check_transfer_status(self, job_run_id, agents_ids=None):
        """
        Check job run status on a list of machines

        :param job_run_id: Job Run ID
        :param agents_ids: iterable object with agents ids, optional
        :return: tuple with dict items:
        {
            "agent_id": <agent_id>,
            "job_run_status": <status>
        }
        """

        try:
            job_run_agents = self._get_job_run_agents(job_run_id)
            logger.debug("Job run agents: {}".format(job_run_agents))
        except ApiError as e:
            logger.error("Failed to get agents info for job run {}".format(e))
            return None
        else:
            logger.info("Successfully get agents info for job run {}".format(job_run_id))

            if agents_ids is None:
                return tuple(
                    {
                        "agent_id": item["agent_id"],
                        "job_run_status": item["status"]
                    } for item in job_run_agents["data"]
                )

            return tuple(
                {
                    "agent_id": item["agent_id"],
                    "job_run_status": item["status"]
                } for item in job_run_agents["data"] if item["agent_id"] in agents_ids
            )

    def _get_local_agent_id(self):
        """
        Get local agent ID

        :return: local agent ID or None in case of error
        """
        try:
            # send request to local agent's api endpoint
            r = requests.get('http://127.0.0.1:{}/api/v2/client'.format(AGENT_API_PORT), timeout=3)
            local_device_id = r.json()['data']['peerid']
        except (requests.RequestException, JSONDecodeError, KeyError) as e:
            logger.error(e)
            return None

        all_agents = self._get_agents()
        logger.debug("All agents: {}".format(all_agents))

        for a in all_agents:
            if a["deviceid"] == local_device_id:
                return a["id"]

        return None

    def check_transfer_status_of_local_agent(self, job_run_id):
        """
        Check job run status on the local agent

        !!! IMPORTANT: Agent's API v2 must be enabled in MC agent profile via 'client_api_enabled=true'

        :param job_run_id: Job Run ID
        :return: transfer status on the local agent
        """

        local_agent_id = self._get_local_agent_id()

        if local_agent_id is None:
            logger.warning("Local agent not found")
            return

        try:
            job_run_local_agent = self._get_job_run_agent(job_run_id, local_agent_id)
        except ApiError as e:
            logger.error("Failed to fetch job run for local agent {}".format(e))
            return None
        else:
            logger.info("Successfully fetched job run for local agent")
            return job_run_local_agent["status"]

    def get_job_run_agents(self, job_run_id):
        """
        Get list of agents for the job run

        :param job_run_id: Job Run ID
        :return: tuple with agents ids
        """

        try:
            job_run_agents = self._get_job_run_agents(job_run_id)
        except ApiError as e:
            logger.error("Failed to get agents info for job run {}".format(e))
            return None
        else:
            logger.info("Successfully get agents info for job run {}".format(job_run_id))

        return tuple(agent['agent_id'] for agent in job_run_agents["data"])


if __name__ == "__main__":
    mc_address = "https://mc.test.com:8443"
    access_token = "fjfjsdlfsadlhfdfhlssjdfjlsh"

    connect_api = ConnectApiExample(mc_address, access_token)

    # print all agents
    agents = connect_api.get_agents()
    print(json.dumps(agents, indent=4, sort_keys=True))

    # create src group
    src_group_id = connect_api.create_group("Src group", (1, 107, 128, 143, 194), description='Source group')

    # create dst group
    dst_group_id = connect_api.create_group("Dst group", (149, 152, 180, 206), description='Source group')

    # delete src group
    connect_api.delete_group(src_group_id)

    # delete dst group
    connect_api.delete_group(dst_group_id)

    # create another src group
    src_group_id = connect_api.create_group("Another Src group", (1, 107, 128, 143), description='Anpther Source group')

    # create another dst group
    dst_group_id = connect_api.create_group("Another Dst group", (149, 152, 180, 206), description='Another Source group')

    # add agents to another src group: 225
    connect_api.add_agents_to_group(src_group_id, (225, ))

    # list another src group agents ids
    src_group_agents = connect_api.get_group_agents(src_group_id)
    print(src_group_agents)

    # add agents to another dst group: 226
    connect_api.add_agents_to_group(dst_group_id, (226, ))

    # list another dst group agents ids
    dst_group_agents = connect_api.get_group_agents(dst_group_id)
    print(dst_group_agents)

    # distribute folder from src group to dst group
    src_group = {
        'id': src_group_id,
        'path': {
            'linux': '/tmp/test',
            'win': r'c:\test',
            'osx': '/tmp/test'
        },
        'permission': "rw"
    }
    dst_groups = [
        {
            'id': dst_group_id,
            'path': {
                'linux': '/tmp/test',
                'win': r'c:\test',
                'osx': '/tmp/test'
            },
            'permission': "ro"
        },
    ]
    job_run_id = connect_api.distribute_folder("Distro job {}".format(time.time()), "Some desc", src_group, dst_groups)

    # check job run status
    job_run_status = connect_api.check_transfer_status(job_run_id)
    print(json.dumps(job_run_status, indent=4, sort_keys=True))

    # check job run status on specific agents
    job_run_status_ = connect_api.check_transfer_status(job_run_id, agents_ids=(1, 149))
    print(json.dumps(job_run_status_, indent=4, sort_keys=True))

    # get job run agents
    job_run_agents = connect_api.get_job_run_agents(job_run_id)
    print(json.dumps(job_run_agents, indent=4, sort_keys=True))

    """
    check job run status on local agent

    !! IMPORTANT: Agent's API v2 must be enabled in MC agent profile via 'client_api_enabled=true'
    """
    job_run_status_for_local_agent = connect_api.check_transfer_status_of_local_agent(job_run_id)
    print(job_run_status_for_local_agent)
