The Nodejs AMQP client library
------------------------

RabbitMQ speaks multiple protocols. This tutorial uses AMQP 0-9-1, which is an open, general-purpose protocol for messaging. There are a number of clients for RabbitMQ in many different languages. We'll use the amqp.node client , the most popular node.js client, in this tutorial.

Install 
```
$ cd examples/Javascript-nodejs
$ npm install amqplib
$ npm install threads_a_gogo
```

Test
----

On your application server, run the web service:
```
$ node webmqx-server.js
```

And, on another terminal, type this:
```
$ curl XXX.XXX.XX.XX/node-test/1
$ curl XXX.XXX.XX.XX/node-test/1/2
$ curl XXX.XXX.XX.XX/node-test/1/2/3
$ curl XXX.XXX.XX.XX/node-test/3/2/1
```
(XXX.XXX.XX.XX is RabbitMQ server's IP)

If echo 'HelloWorld', it works.
Enjoy it!


