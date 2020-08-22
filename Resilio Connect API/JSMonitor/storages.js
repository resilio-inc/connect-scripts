// @ts-check

module.exports = {
    addNewStorage,
    deleteStorage,
    getStorages,
};

const { initializeMCParams, getAPIRequest, postAPIRequest, deleteAPIRequest, } = require('./communication');

function getStorages() {
    var getStoragesResponse = (resolve, reject) => {
        getAPIRequest("/api/v2/storages")
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(getStoragesResponse);  
}

function addNewStorage(type, name, desc, access_id, access_secret, bucket, region) {
    var addNewStorageResponse = (resolve, reject) => {
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
            resolve(APIResponse);
        });
    }
    return new Promise(addNewStorageResponse);  
}

function deleteStorage(storageID) {
    var deleteStorageResponse = (resolve, reject) => {
        deleteAPIRequest("/api/v2/storages/" + storageID)
        .then((APIResponse) => {
            resolve(APIResponse);
        });
    }
    return new Promise(deleteStorageResponse);  
}

