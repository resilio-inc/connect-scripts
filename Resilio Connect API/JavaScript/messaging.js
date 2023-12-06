// @ts-check

module.exports= {
  initializeTexting,
  sendMessage
};

var accountFrom = "";
var accountSid = "";
var accountToken = "";
var client;

/**
 * 
 * @param {string} from 
 * @param {string} Sid 
 * @param {string} Token 
 */
function initializeTexting(from, Sid, Token) {
  accountFrom = from;
  accountSid = Sid;
  accountToken = Token;
  client = require('twilio')(accountSid, accountToken);
}

function sendMessage(to, body) {
  client.messages.create({
    body: body,
    from: accountFrom,
    to: to,
  })
  .then(message => console.log("Twilio message and status: \"" + message.body + "\"; " + message.status))
}
