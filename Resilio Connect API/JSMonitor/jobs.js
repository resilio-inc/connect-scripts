// @ts-check

module.exports = {
    addJob,
    appendToJobAgentList,
};

const { initializeMCParams, getAPIRequest, postAPIRequest } = require('./communication');

function appendToJobAgentList(list, id, permission, path) {
    list = list.concat({
        "id": id,
        "permission": permission,
        "path": {"linux": path, "win": path, "osx": path, "android": path, "xbox": path },
    });
    return list;
}

function addJob(name, desc, type, agents) {

    const jobInfo = 
    {
        "name": name,
        "description": desc,
        "type": type,
        "agents": agents,
    };

    postAPIRequest("/api/v2/jobs", jobInfo)
    .then((APIResponse) => {
        console.log("MC Response: " + APIResponse);
    });
}