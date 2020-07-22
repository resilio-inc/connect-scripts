//module.exports = {};

module.exports = {
    updateAgentList
};

const { getAgentProperty, setAgentProperty } = require('./data-store');
const { getAPIRequest } = require('./communication');

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
    // call api
    // update the data store
}

