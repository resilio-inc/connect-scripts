import sys
import json

sys.path.append("./")
from communication import getAPIRequest

def getAgentList() -> json:
    return getAPIRequest("/api/v2/agents")