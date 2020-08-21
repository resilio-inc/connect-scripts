// @ts-check

const { initializeMCParams, getAPIRequest, postAPIRequest } = require('./communication');
const { getAgentProperty, setAgentProperty } = require('./data-store');
const { getJobProperty, setJobProperty } = require('./data-store');
const { enumerateAgents } = require('./data-store');
const { updateAgentList, updateJobsPerAgent, periodicAgentUpdate } = require('./agents');
const { initializeTexting, sendMessage } = require ('./messaging');
const { addNewStorage } = require('./storages');
const { findArrayDiff } = require('./utils');

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
//initializeMCParams("demo29.resilio.com", 8443, "6BZK5YQ6ER72NWP2GB7MYKEGA2AQZUXCCEVU7G7H4JTDGLDRNPMA");
// read/write:
initializeMCParams("demo29.resilio.com", 8443, "6DJXHMQIR4NWJKPOGODURZQSZMMN47WYKLGISON6P3PVMK7JOKJQ");

getAPIRequest("/api/v2/info")
.then((APIResponse) => {
    console.log("MC Info: " + APIResponse);
});

addNewStorage("s3", "s3 storage 2", "some desc", 
    "ABSGNHYTDR9495969784", "ABSGNHYTDR9495969784ABSGNHYTDR949596978=",
    "bucketname", "gg-hht-9");
