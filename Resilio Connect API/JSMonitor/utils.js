module.exports = {
    findArrayDiff,
};

function findArrayDiff(a1, a2) {
    let a = []
    let diff = [];

    for (var i = 0; i < a1.length; i++) {
        a[a1[i]] = true;
    }

    for (var i = 0; i < a2.length; i++) {
        if (a[a2[i]]) {
            delete a[a2[i]];
        } else {
            a[a2[i]] = true;
        }
    }

    for (var k in a) {
        diff.push(Number(k));
    }

    return diff;
}
