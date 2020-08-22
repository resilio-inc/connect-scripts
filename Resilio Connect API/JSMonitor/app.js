// @ts-check

const { initializeMCParams, getAPIRequest, postAPIRequest } = require('./communication');
const { getAgentProperty, setAgentProperty } = require('./data-store');
const { getJobProperty, setJobProperty } = require('./data-store');
const { enumerateAgents } = require('./data-store');
const { updateAgentList, updateJobsPerAgent, periodicAgentUpdate } = require('./agents');
const { initializeTexting, sendMessage } = require ('./messaging');
const { addNewStorage, deleteStorage } = require('./storages');
const { addJob, startJob, getJobRunStatus, getJobRunID, monitorJob, appendToJobAgentList, deleteJob } = require('./jobs');
const { findArrayDiff } = require('./utils');
const { exit } = require('process');

function testAgentList() {
    updateAgentList();
    updateJobsPerAgent();
    setTimeout(function(){console.log ("Name of Agent 1 = " + getAgentProperty(1, "name"));}, 3000);
    setTimeout(function(){console.log ("Is Agent 1 online = " + getAgentProperty(1, "status"));}, 3000);
    setTimeout(function(){console.log ("Agents in Job 2 = " + getJobProperty(2, "agents"));}, 3000);
    setTimeout(function() {console.log("List of all Agents = " + enumerateAgents());}, 3000);
}

function testSMS() {
    initializeTexting('+12029725018', process.env.TWILIOSID, process.env.TWILIOTOKEN);
    // TO DO: remove this commented out line to send a message to the number specified there
    //sendMessage('5105171086', 'hello dawg');
}

//console.log(findArrayDiff([1, 5, 17, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160], [1, 5, 17, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 165]));

function onNewAgents(diffArray) {
    console.log("ALERT: The new agents this cycle are " + diffArray);
}

function onNoAgentsChange() {
    console.log("ALERT: No new agents this cycle");
}

function testAgentUpdate() {
    periodicAgentUpdate(onNewAgents, onNoAgentsChange, 10000);
}

// read-only:
//initializeMCParams("demo29.resilio.com", 8443, "READ_ONLY-KEY");
// read/write:
initializeMCParams("demo29.resilio.com", 8443, process.env.RESILIO_AUTH_TOKEN);

// get the MC version
getAPIRequest("/api/v2/info")
.then((APIResponse) => {
console.log("MC Info: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const code = APIResponse["code"];
if (code == 401) {
    throw("invalid auth token");
}

// get the list of agents
updateAgentList()       // this populates the "data-store"   
.then((APIResponse) => { 
console.log("\nMC Info: " + APIResponse);

// add a storage bucket
addNewStorage("s3", "s3 storage 2", "some desc", 
        process.env.RESILIO_TEST_S3_BUCKET_ACCESS_ID,
        process.env.RESILIO_TEST_S3_BUCKET_SECRET,
        "ilan-test-2", "us-west-1")
.then((APIResponse) => { 
console.log("\nMC Response: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const storageID = APIResponse["id"];

// enumerate the Agents
var agentList = enumerateAgents();  // this just reads the list from the "data-store"

// add a distribution job
var jobAgentList = [];
// we use the first 2 Agents in the agentList
jobAgentList = appendToJobAgentList(jobAgentList, agentList[0], "rw", "Project Files", storageID);   
jobAgentList = appendToJobAgentList(jobAgentList, agentList[1], "ro", "/tmp/Project Files");
addJob("Test Distribution Job 1", "A demo distribution job", "distribution", jobAgentList)
.then((APIResponse) => { 
console.log("\nMC Response: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const jobID = APIResponse["id"];

// start the job
startJob(jobID)
.then((APIResponse) => { 
console.log("\nMC Response: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const runID = APIResponse["id"];

// check on the status of the job every x msec
monitorJob(runID, cleanupWhenDone, 5000);

// add a synchronization job
var jobAgentList = [];
// we use the first 2 Agents in the agentList
jobAgentList = appendToJobAgentList(jobAgentList, agentList[0], "rw", "Watch Folder 1", storageID);   
jobAgentList = appendToJobAgentList(jobAgentList, agentList[1], "rw", "/tmp/Watch Folder 1");
addJob("Test Sync Job 1", "A demo sync job", "sync", jobAgentList)
.then((APIResponse) => { 
console.log("\nMC Response: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const jobID = APIResponse["id"];

// no need to start sync jobs.  

// need to get the runID for this job
getJobRunID(jobID)
.then((APIResponse) => { 
console.log("\nMC Response: " + APIResponse);
APIResponse = JSON.parse(APIResponse);
const runID = APIResponse.data[0]["id"];
    
// check on the status of the job every x msec
monitorJob(runID, cleanupWhenDone, 5000);

});
});
});
});
});
});
});


function cleanupWhenDone(jobID) {
    // cleanup

    // delete the job
    deleteJob(jobID)
    .then((APIResponse) => { 
    console.log("\nMC Info: " + APIResponse);

    // delete the storage
    //deleteStorage(storageID)
    //.then((APIResponse) => { 
    //console.log("\nMC Info: " + APIResponse);
    });
}
