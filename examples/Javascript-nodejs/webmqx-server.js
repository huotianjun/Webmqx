#!/usr/bin/env node

var amqp = require('amqplib/callback_api');

// Here, set the RabbitMQ server's IP or host.
amqp.connect('amqp://guest:guest@localhost:5672', function(err, conn) {
  conn.createChannel(function(err, ch) {
	var ex = 'webmqx';

	ch.assertQueue('', {exclusive: true, autoDelete: true}, function(err, q) {
		console.log(" [*] Waiting for http requests in %s. To exit press CTRL+C", q.queue);

		// Here, you can bind the path which you want to 'pull'.
		ch.bindQueue(q.queue, ex, '/node-test/1');
		ch.bindQueue(q.queue, ex, '/node-test/1/2');
		ch.bindQueue(q.queue, ex, '/node-test/1/2/3');
		ch.bindQueue(q.queue, ex, '/node-test/3/2/1');

		ch.prefetch(1);
		console.log(' [x] Awaiting RPC requests');
		ch.consume(q.queue, function (msg) {

			var rpc_request = JSON.parse(msg.content.toString());


			var response = handle(rpc_request);

			var response_body = {  
				"headers": {"content-type":"text/html"}, 
				"body": response   
			}; 
			 
			var response_str = JSON.stringify(response_body); 

			ch.sendToQueue(msg.properties.replyTo,
							new Buffer(response_str),
							{correlationId: msg.properties.correlationId});

			ch.ack(msg);
		});
    });
  });
});

function handle(rpc_request) {
	var http_req = rpc_request['req'];
	var http_body = rpc_request['body'];

	console.log(" [http_req] ", http_req);
	console.log(" [http_body] ", http_body);

	return 'HelloWorld';
}
