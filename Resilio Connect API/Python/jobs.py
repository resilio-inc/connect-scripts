import sys
import json
import time

sys.path.append("./")
from communication import getAPIRequest, postAPIRequest

def appendToJobAgentList(list, id, permission, path) -> json:
    list.append({
        "id": id,
        "permission": permission,
        "path": {"linux": path, "win": path, "osx": path, "android": path, "xbox": path }
    })
    return list

def addJob(name, desc, type, agents) -> json:
    jobInfo = {
        "name": name,
        "description": desc,
        "type": type,
        "agents": agents
    }
    return postAPIRequest("/api/v2/jobs", jobInfo)

def startJob(jobID) -> json:
    jobInfo = {
        "job_id": jobID
    }
    return postAPIRequest("/api/v2/runs", jobInfo)

def getJobRunStatus(runID) -> json:
    return getAPIRequest("/api/v2/runs/" + str(runID))

class jobMonitor:
    def __init__(self, runID, finishedCallbackFunction):
        self.monitorJobID = 0
        self.monitoredRunID = runID
        self.monitorJobStatus = ""
        self.monitorErrCode = 200
        self.monitorCallback = finishedCallbackFunction

    def getJobStatus(self) -> str:
        return self.monitorJobStatus
    
    def getErrCode(self) -> int:
        return self.monitorErrCode

    def updateJobRunStatus(self):
        runStatus = getJobRunStatus(self.monitoredRunID)
        self.monitorJobID = runStatus["job_id"]
        self.monitorJobStatus = runStatus["status"]
        try:
            self.monitorErrCode = runStatus["code"]
        except:
            self.monitorErrCode = 0
        if (self.monitorJobStatus == "finished"):
            self.monitorCallback(self.monitorJobID)

jobRuns = {}

def monitorJob(runID, finishedCallbackFunction, monitorInterval):
    if (not runID in jobRuns):
        # new job run to monitor
        jobRuns[runID] = jobMonitor(runID, finishedCallbackFunction)

    while ((jobRuns[runID].getJobStatus() != "finished") and (jobRuns[runID].getErrCode != 404)):
        # this should become multi-threaded to monitor several jobs
        time.sleep(monitorInterval)
        jobRuns[runID].updateJobRunStatus()
    # remove from the jobRuns dict
    jobRuns.pop(runID, None)
