module.exports = {
    findArrayDiff,
};

// creates a new array that contains the values that the lists do not share. 
// a1 would be the newest array of agents, and a2 would be the older array of agents
function findArrayDiff(a1, a2) {
    var diff = [];

    diff = a1.filter(x => !a2.includes(x)); // filters the elements from a1 that are not included in a2 into an array.
    
    return diff;
}

