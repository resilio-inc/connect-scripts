// @ts-check

module.exports= {
  initializeTexting,
  SendMessage
};


function initializeTexting(from, Sid, Token) {
    mcFrom = from;
    mcSid = Sid;
    mcToken = Token;
}


var twilio = require('twilio');

function SendMessage(to, body) {
    
const accountSid = mcSid;
const authToken = mcToken;
const client = require('twilio')(accountSid, authToken);

client.messages
      .create({
         body: body,
         from: mcFrom,
         to: to,
      })
      .then(message => console.log(message.status))
}



