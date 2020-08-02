// @ts-check

module.exports = {
    initializeMCParams,
    getAPIRequest,
};

var https = require('https');

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

function getAPIRequest(APIReq) {
    var APIResponse = (resolve, reject) => {
        var options = {
            headers:{Authorization: mcToken},
            host: mcURL,
            port: mcPort,
            path: APIReq
        }
    
        https.get(options, function(res) {
          var data = '';
    
          res.on('data', function(chunk) {
            data += chunk;
          });
    
          res.on('end', () => {
            resolve(data); 
    
          }).on('error', (err) => {
            console.log("there was an error:" + err);
            reject(err);
          }); 
          
        });
      }
      return new Promise(APIResponse)
}

