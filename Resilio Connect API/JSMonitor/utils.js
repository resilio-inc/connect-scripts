module.exports = {
    findArrayDiff,
};

// creates a new array that contains the values that the lists do not share
function findArrayDiff(a1, a2) {
    var diff = [];

    diff = a1.filter(x => !a2.includes(x))           // filters the elements from a1 that are not included a2 into an array.
           .concat(a2.filter(x => !a1.includes(x))); // filters the elements from a2 that are not in a1 into an array
                                                     // using the concat() method, both arrays are taking and merged into a new array
    
    return diff;
}
