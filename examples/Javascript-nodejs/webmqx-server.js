#!/usr/bin/env node

var amqp = require('amqplib/callback_api');

amqp.connect('amqp://localhost', function(err, conn) {
  conn.createChannel(function(err, ch) {
	var ex = 'webmqx';

	ch.assertQueue('', {exclusive: true, autoDelete: true}, function(err, q) {
		console.log(" [*] Waiting for http requests in %s. To exit press CTRL+C", q.queue);
		ch.bindQueue(q.queue, ex, '/nodejs-test/1');
		ch.bindQueue(q.queue, ex, '/nodejs-test/1/2');
		ch.bindQueue(q.queue, ex, '/nodejs-test/1/2/3');
		ch.bindQueue(q.queue, ex, '/nodejs-test/3/2/1');

		ch.prefetch(1);
		console.log(' [x] Awaiting RPC requests');
		ch.consume(q.queue, function (msg) {
			//var n = parseInt(msg.content.toString());

			console.log(" [.] %s", msg.content.toString());

			var response = handle();

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

function handle() {
	return 'HelloWorld';
}
