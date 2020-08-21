// @ts-check

module.exports = {
    initializeMCParams,
    getAPIRequest,
    postAPIRequest,
};

var https = require('https');

var mcURL = "";
var mcPort = 0;
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
            headers: {"Authorization": mcToken},
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


function postAPIRequest(APIReq, postData) {
  var APIResponse = (resolve, reject) => {
    postData = JSON.stringify(postData);
      var options = {
          headers: {
            "Authorization": mcToken,
            "Content-Type": "application/json",
            "Content-Length": postData.length
          },
          host: mcURL,
          port: mcPort,
          path: APIReq,
          method: "POST"
      }
  
      const req = https.request(options, function(res) {
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
      req.write(postData);
      req.end();
    }
    return new Promise(APIResponse)
}
