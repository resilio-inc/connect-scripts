// @ts-check

module.exports = {
    setAgentProperty,
    getAgentProperty,
    setJobProperty,
    getJobProperty,
    enumerateAgents,
};

var agents = {};
var jobs = {};

function setAgentProperty(id, propertyName, value) {
    if (!agents.hasOwnProperty(id)) {
        agents[id] = {[propertyName]: value};
    } else {
        agents[id][propertyName] = value;
    }
}

function getAgentProperty(id, propertyName) {
    if (agents.hasOwnProperty(id) && agents[id].hasOwnProperty(propertyName)) {
        return agents[id][propertyName];
    } else {
        throw "No such id or propertyName - " + id + "," + propertyName;
    }
}

function setJobProperty(id, propertyName, value) {
    if (!jobs.hasOwnProperty(id)) {
        jobs[id] = {[propertyName]: value};
    } else {
        jobs[id][propertyName] = value;
    }
}

function getJobProperty(id, propertyName) {
    if (jobs.hasOwnProperty(id) && jobs[id].hasOwnProperty(propertyName)) {
        return jobs[id][propertyName];
    } else {
        throw "No such id or propertyName";
    }    
}

function enumerateAgents() {
    let listAllAgents = [];
    
    for(var key in agents) {
        listAllAgents.push(Number(key));
    }
    
    return listAllAgents;
}

