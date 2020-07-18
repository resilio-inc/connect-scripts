// @ts-check
module.exports = {
    setAgentProperty,
    getAgentProperty,
    setJobProperty,
    getJobProperty,
};

var agents = {};
var jobs = {};

function setAgentProperty(id, propertyName, value) {
    agents[id] = {[propertyName]: value};
}

function getAgentProperty(id, propertyName) {
    return agents[id][propertyName];
}

function setJobProperty(id, propertyName, value) {
    jobs[id] = {[propertyName]: value};
}

function getJobProperty(id, propertyName) {
    return jobs[id][propertyName];
}
