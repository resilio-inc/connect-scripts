// @ts-check

module.exports = {
    addNewStorage,
};

const { initializeMCParams, getAPIRequest, postAPIRequest } = require('./communication');

function addNewStorage(type, name, desc, access_id, access_secret, bucket, region) {

    const storageInfo = 
    {
        "type": type,
        "name": name,
        "description": desc,
        "config": {
            "access_id": access_id,
            "access_secret": access_secret,
            "bucket": bucket,
            "region": region
        }
    };

    postAPIRequest("/api/v2/storages", storageInfo)
    .then((APIResponse) => {
        console.log("MC Response: " + APIResponse);
    });
  
}