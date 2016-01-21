var WebSocket = require('ws');
var wsserver = process.argv[2];
var stdargs = "";
var ignorefirst = "true";

function connectWebSocket()
{
  websocket = new WebSocket(wsserver);
  websocket.onopen = function(evt) { onOpen(evt) };
  websocket.onclose = function(evt) { onClose(evt) };
  websocket.onmessage = function(evt) { onMessage(evt) };
  websocket.onerror = function(evt) { onError(evt) };
}

function onOpen(evt)
{
  var authjson = '{ "namespace":"rpc", "name":"auth", "id":"authrequest", "args": { "username":"' + process.argv[3] +'", "password":"' + process.argv[4] + '" } }';
  nstatus = "auth";
  wstatus = "idle";
  doSend(authjson);
  doSend(stdargs);
}

function onClose(evt)
{
}

function onError(evt)
{
  console.log(evt);
}

function onMessage(evt)
{
  var jsonobj = JSON.parse(evt.data);
  if ( ignorefirst == "true" ) {
    ignorefirst = "false";
    return;
  } else {
    console.log(JSON.stringify(jsonobj, null, 2));
  }
  websocket.close();
}

function doSend(message)
{
  //console.log('Sent: ' + message);
  websocket.send(message);
}

function readStdIn(msg)
{
  stdargs = msg;
}

process.stdin.resume();
process.stdin.setEncoding('utf8');

process.stdin.on('data', function(message) {
  readStdIn(message);
});

connectWebSocket();
