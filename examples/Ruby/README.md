The Bunny client library
------------------------

RabbitMQ speaks multiple protocols. This tutorial uses AMQP 0-9-1, which is an open, general-purpose protocol for messaging. There are a number of clients for RabbitMQ in many different languages. We'll use the Bunny, the most popular Ruby client, in this tutorial.

Install Bunny using Rubygems:
```
$ gem install bunny --version ">= 2.5.1"
```

Test
----

On your application server, run the web service:
```
$ ruby webmqx-server.rb
```

And, on another terminal, type this:
```
$ curl XXX.XXX.XX.XX/ruby-test/1
$ curl XXX.XXX.XX.XX/ruby-test/1/2
$ curl XXX.XXX.XX.XX/ruby-test/1/2/3
$ curl XXX.XXX.XX.XX/ruby-test/3/2/1
```
(XXX.XXX.XX.XX is RabbitMQ server's IP)

If echo 'HelloWorld', it works.
Enjoy it!


