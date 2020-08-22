// @ts-check

module.exports = {
    addJob,
    startJob,
    getJobRunStatus,
    updateJobRunStatus,
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

// check on the status of the job after x msec
var monitorJobID;
var monitoredRunID;
var monitorInterval;
var monitorStatus;
var monitorCode;
var monitorCallback
function updateJobRunStatus(runID, interval, finishedCallbackFunction) {
    monitoredRunID = runID;
    monitorInterval = interval;
    monitorCallback = finishedCallbackFunction;
    getJobRunStatus(runID)
    .then((APIResponse) => { 
        console.log("\nMC Info: " + APIResponse);
        APIResponse = JSON.parse(APIResponse);
        monitorJobID = APIResponse["job_id"];
        monitorStatus = APIResponse["status"];
        monitorCode = APIResponse["code"];
    });
    if ((monitorStatus != "finished") && (monitorCode != 404)){
        setTimeout(() => { updateJobRunStatus(monitoredRunID, monitorInterval, monitorCallback); }, monitorInterval);
    } else {
        monitorStatus = "";
        monitorCode = 0;
        finishedCallbackFunction(monitorJobID)
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

