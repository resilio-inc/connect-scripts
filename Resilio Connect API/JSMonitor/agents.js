// @ts-check

module.exports = {
    updateAgentList,
    updateJobsPerAgent,
    periodicAgentUpdate
};

const { getAgentProperty, setAgentProperty, enumerateAgents } = require('./data-store');
const { setJobProperty } = require('./data-store')
const { getAPIRequest } = require('./communication');
const { findArrayDiff } = require('./utils');

function updateAgentList() {
    getAPIRequest("/api/v2/agents")
    .then((APIResponse) => {
        console.log("response = " + APIResponse);
    
        const agentsJson = APIResponse; 
        const agents = JSON.parse(agentsJson);
    
        for (let index = 0; index < agents.length; index++) {
            const element = agents[index];
            setAgentProperty(element.id, "name", element.name);
            setAgentProperty(element.id, "status", element.online);
        }
    });
}

function updateJobsPerAgent() {
    getAPIRequest("/api/v2/jobs")
    .then((APIResponse) => {
        
        const jobs = JSON.parse(APIResponse);

        for(var i = 0; i < jobs.length; i++) {
            const element = jobs[i];
            const agentArray = [];

            for(var x = 0; x < jobs[i]["agents"].length; x++){ 
              const element2 = jobs[i].agents[x];
              agentArray.push(element2.id);
            }

            setJobProperty(element.id, "agents", agentArray);
        }
    });
}

class updateListofAgents {

    constructor() {
        this.updatedList = [];
        this.arrayDiff = [];
        this.prevList = [];
        this.callCounter = 0;
    }
    
    periodicUpdate(onDifferentCallback, onNoChangeCallback) {
        this.prevList = this.updatedList;
        this.updatedList = enumerateAgents();

        this.arrayDiff = findArrayDiff(this.updatedList, this.prevList);
        if (this.callCounter != 0) {
            if (this.arrayDiff.length != 0) {
                onDifferentCallback(this.arrayDiff);
            } else {
                onNoChangeCallback();
            }
        }
        updateAgentList();
        this.callCounter++;
    }

}

var update = new updateListofAgents;

function periodicAgentUpdate(onDifferentCallback, onNoChangeCallback, freq) {
    update.periodicUpdate(onDifferentCallback, onNoChangeCallback);
    setTimeout(() => {periodicAgentUpdate(onDifferentCallback, onNoChangeCallback, freq)}, freq);
}

