module.exports = {
    initializeMCParams,
    getAPIRequest,
};

var mcURL = "";
var mcPort = "";
var mcToken = "";

/**
 * 
 * @param {string} url 
 * @param {number} port 
 * @param {string} token 
 */
function initializeMCParams(url, port, token) {
    mcURL = url;
    mcPort = port;
    mcToken = "Token " + token;
}

function getAPIRequest(APIreq) {
    // TO DO: replace with real code
    return '[{"id": 2, "name": "Cleanup"},{"id": 17, "name": "Moshe"}]';
}
