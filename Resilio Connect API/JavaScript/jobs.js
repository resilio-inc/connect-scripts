// @ts-check

module.exports = {
    addJob,
    startJob,
    getJobRunStatus,
    getJobRunID,
    monitorJob,
    deleteJob,
    appendToJobAgentList,
};

const { initializeMCParams, getAPIRequest, postAPIRequest, deleteAPIRequest } = require('./communication');

function appendToJobAgentList(list, id, permission, path, storageID) {
    list = list.concat({
        "id": id,
        "permission": permission,
        "path": {"linux": path, "win": path, "osx": path, "android": path, "xbox": path },
        "storage_config_id": storageID,
    });
    return list;
}

function addJob(name, desc, type, agents) {
    var addJobResponse = (resolve, reject) => {

        const jobInfo = 
        {
            "name": name,
            "description": desc,
            "type": type,
            "agents": agents,
        };

        postAPIRequest("/api/v2/jobs", jobInfo)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(addJobResponse);
}

function startJob(jobID) {
    var startJobResponse = (resolve, reject) => {

        const jobInfo = 
        {
            "job_id": jobID,
        };

        postAPIRequest("/api/v2/runs", jobInfo)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(startJobResponse);
}

function getJobRunStatus(runID) {
    var getJobRunStatusResponse = (resolve, reject) => {
        getAPIRequest("/api/v2/runs/" + runID)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(getJobRunStatusResponse);
}

function getJobRunID(jobID) {
    var getJobRunIDResponse = (resolve, reject) => {
        getAPIRequest("/api/v2/runs?job_id=" + jobID)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(getJobRunIDResponse);
}

class jobMonitor {

    constructor(runID, finishedCallbackFunction) {
        this.monitorJobID = 0;
        this.monitoredRunID = runID;
        this.monitorJobStatus = "";
        this.monitorErrCode = 200;
        this.monitorCallback = finishedCallbackFunction;
    }

    getJobStatus() {
        return this.monitorJobStatus
    }

    getErrCode() {
        return this.monitorErrCode
    }

    updateJobRunStatus() {
        getJobRunStatus(this.monitoredRunID)
        .then((APIResponse) => { 
            console.log("\nMC Info: " + APIResponse);
            APIResponse = JSON.parse(APIResponse);
            this.monitorJobID = APIResponse["job_id"];
            this.monitorJobStatus = APIResponse["status"];
            this.monitorErrCode = APIResponse["code"];
            if (this.monitorJobStatus == "finished") {
                this.monitorCallback(this.monitorJobID);
            }
        });
    }
}

var jobRuns = {};

function monitorJob(runID, finishedCallbackFunction, monitorInterval) {
    if (!jobRuns.hasOwnProperty(runID)) {
        jobRuns[runID] = new jobMonitor(runID, finishedCallbackFunction);
    }
    if ((jobRuns[runID].getJobStatus() != "finished") && (jobRuns[runID].getErrCode != 404)) {
        setTimeout(() => { 
            jobRuns[runID].updateJobRunStatus();
            monitorJob(runID, finishedCallbackFunction, monitorInterval);
        }, monitorInterval);
    } else {
        delete jobRuns[runID];
    }
} 

function deleteJob(jobID) {
    var deleteJobResponse = (resolve, reject) => {
        deleteAPIRequest("/api/v2/jobs/" + jobID)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(deleteJobResponse);
}

