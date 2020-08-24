// @ts-check

module.exports = {
    initializeMCParams,
    getAPIRequest,
    postAPIRequest,
    deleteAPIRequest,
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
      headers: { "Authorization": mcToken },
      host: mcURL,
      port: mcPort,
      path: APIReq
    }

    https.get(options, function (res) {
      var data = '';

      res.on('data', function (chunk) {
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


function APIRequest(APIReq, method, bodyData) {
  var APIResponse = (resolve, reject) => {
    if (bodyData.length != "") {
      bodyData = JSON.stringify(bodyData);
    }
    var options = {
      headers: {
        "Authorization": mcToken,
        "Content-Type": "application/json",
        "Content-Length": bodyData.length
      },
      host: mcURL,
      port: mcPort,
      path: APIReq,
      method: method,
    }

    const req = https.request(options, function (res) {
      var data = '';

      res.on('data', function (chunk) {
        data += chunk;
      });

      res.on('end', () => {
        resolve(data);

      }).on('error', (err) => {
        console.log("there was an error:" + err);
        reject(err);
      });

    });
    req.write(bodyData);
    req.end();
  }
  return new Promise(APIResponse)
}

function postAPIRequest(APIReq, postData) {
  return APIRequest(APIReq, "POST", postData);
}

function deleteAPIRequest(APIReq) {
  return APIRequest(APIReq, "DELETE", "");
}

