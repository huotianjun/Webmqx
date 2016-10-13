Install PHP AMQP Client Library
-------------------------------

RabbitMQ speaks multiple protocols. This tutorial covers AMQP 0-9-1, which is an open, general-purpose protocol for messaging. There are a number of clients for RabbitMQ in many different languages. We'll use the php-amqp in this tutorial.

First, you must download and build RabbitMQ C library( https://github.com/alanxz/rabbitmq-c ), commonly known as librabbitmq (since php-amqp>=1.6.0 librabbitmq >= 0.5.2 required, >= 0.6.0 recommended, see release note).

Then, git php-amqp from here: https://github.com/pdezwart/php-amqp
Build it to amqp.so, which should be copied to php module's directory: 

```
./configure --with-php-config='path to php-config's direcroty'  --with-amqp   --with-librabbitmq-dir='path to RabbitMQ C library's directory' 
$ make
$ make install
```

finally, add 'extension=amqp.so' to php.ini .

Test
----

On your applicatoin server's host, startup the test server:
```
$ php webmqx-server.php&
```
And, on another terminal, type this:
```
curl -i http://XXX.XXX.XX.XX/php-test/1/2/3
curl -i http://XXX.XXX.XX.XX/php-test/3/2/1
```
(XXX.XXX.XX.XX is the RabbitMQ server's IP)

If echo 'HelloWorld', it works. 
Enjoy it!
