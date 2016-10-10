Webmqx
======

- Webmqx is a HTTP server plugin for RabbitMQ server, and was built in a HTTP server of Cowboy. 

- Because it uses RabbitMQ client's framework in your web services, so Webmqx client can easily be **embedded** in any other application server which running anywhere, written in any language. 

- It is easy to use: no parameterize with web server module of Webmqx,  and all HTTP requests routing to web service by the settings in your application.

- It can also be used as HTTP load-balancing proxy server.

- Webmqx is written in Erlang.

Goals
-----

Webmqx aims to docker/microsevices. 

TO-DOs
------

- Other webmqx examples of framework in web service by mainstream languages, Java/Python/Ruby/C#/Javascript/Go/Elixer/etc.

- Docker images for webmqx client's frameworks.

- End-to-end monitor/trace/debug/test of web services.


Install Webmqx plugin
---------------------

 *  Install erlang/OTP.

 *  Install RabbitMQ server.

 *  Install Webmqx plugins:

The easiest	way	to utilize the webmqx plugin is by installing the full codes available on Github.
```
git clone https://github.com/huotianjun/Webmqx.git
cd webmqx
make dist
```
The plugin's files(*.ez) must be copy to plugins directory of the RabbitMQ distribution . 
To enable it:

```
./rabbitmq-plugins enable webmqx
```

Then, restart rabbitmq-server
```
./rabbitmqctl stop
./rabbitmq-server&
```
**If there are some errors for duplicate plugin files, remove the duplicated ones.**

Default HTTP port used by the plugin is `80`.

After all, test in shell: (XXX.XXX.XX.XX is Webmqx server's IP)
```
curl -i http://XXX.XXX.XX.XX/test/HelloWorld
```
If echo 'HelloWorld', it works.

How to use in web service
-------------------------

For example of PHP (with pthreads enabled), the web service's framework is like this (reference in http://www.rabbitmq.com/tutorials/tutorial-six-php.html , and its PHP amqp-client's library supported by https://github.com/pdezwart/php-amqp ): 


```PHP

<?php
class Handler extends Thread {
	public function __construct(AMQPEnvelope $message)
	{
		$this->message = $message;
	}

	public function run(){
		// Establish connection to AMQP for rpc response.
		// Attention: don't use $this->amqp_connection here.
		$amqp_connection = new AMQPConnection();
		$amqp_connection->setHost('127.0.0.1'); // Webmqx Server IP.
		$amqp_connection->setLogin('guest'); 
		$amqp_connection->setPassword('guest');
		$amqp_connection->connect();
		$amqp_channel = new AMQPChannel($amqp_connection);
		$amqp_exchange = new AMQPExchange($amqp_channel);
		
		// Parse webmqx rpc request message.
		$rpc_request = json_decode($this->message->getBody(), true);
		$http_body = $rpc_request['body'];
		$http_request = $rpc_request['req'];
		$http_path = $http_request['path'];
		$http_query = $http_request['qs'];

		$attributes = array(
							'correlation_id' => $this->message->getCorrelationId()
						);

		$result = $this->handle($http_path, $http_query, $http_body);

		// Return for http response.
		$amqp_exchange->publish((string)($result),
									$this->message->getReplyTo(), 
									AMQP_NOPARAM,
									$attributes
								);

		$amqp_connection->disconnect();
	}

	public function handle($http_path, $http_query, $http_body) {
		//
		// Your application codes would be written in here.
		//

		// Just for example:
		$response_body = 'Hello World';	

		$response = array (
							'headers' => array ( 'content-type' => 'text/html') ,
							'body' => $response_body 
						);
		
		return json_encode($response);
	}
}

class WebmqxServer {
	private $connection;
	private $channel;
	private $queue;
	private $exchange;

	public function __construct()
	{
	}
	
	private function amqp_connect() {
		//Establish connection to AMQP to consume rpc request.
		$this->connection = new AMQPConnection();
		$this->connection->setHost('127.0.0.1'); // Webmqx server IP.
		$this->connection->setLogin('guest');
		$this->connection->setPassword('guest');
		$this->connection->connect();

		//Declare Channel
		$this->channel = new AMQPChannel($this->connection);
		$this->channel->setPrefetchCount(1);

		// This is a non-consistent queue, just for this process.
		$this->queue = new AMQPQueue($this->channel);
		$this->queue->setFlags(AMQP_EXCLUSIVE | AMQP_AUTODELETE);
		$this->queue->declareQueue();

		// Exchange must set to 'webmqx'.
		$exchange_name = 'webmqx';

		// There can set many http request paths which you want to handle, for example:
		$binding_key1 = '/1';
		$binding_key2 = '/1/2';
		$binding_key3 = '/1/2/3';
		$binding_key4 = '/3/2/1';

		$this->queue->bind($exchange_name, $binding_key1);
		$this->queue->bind($exchange_name, $binding_key2);
		$this->queue->bind($exchange_name, $binding_key3);
		$this->queue->bind($exchange_name, $binding_key4);
	}

	public function init() {

		$this->amqp_connect();	

		// This callback to handle a http_rpc_request from Webmqx server.
		$callback_func = function(AMQPEnvelope $message, AMQPQueue $q) {
			// A rpc request, a thread.
			$handler = new Handler($message);
			$handler->start() && $handler->join();
			$q->ack($message->getDeliveryTag());
		};
		
		$continue = True;
		while($continue){
			try {
				$this->queue->consume($callback_func);
			} catch(AMQPQueueException $ex) {
				print_r($ex);
				$continue = False;
			} catch(Exception $ex) {
				print_r($ex);
				$continue = False;
			}
		}
		$this->connection->disconnect();
	}		
}

$WebmqxServer = new WebmqxServer;
$WebmqxServer->init() or print 'no request data';

?>

```

Start the web service:
```
php webmqx-server.php&
```
**Atention: you can start it many times, and it also can be started on several hosts.** 

Test:
```
curl -i http://XXX.XXX.XX.XX/1/2/3
curl -i http://XXX.XXX.XX.XX/3/2/1
```
If echo 'HelloWorld', it works.


Other languages, reference to:

- Python: http://www.rabbitmq.com/tutorials/tutorial-six-python.html
- Java: http://www.rabbitmq.com/tutorials/tutorial-six-java.html
- Ruby: http://www.rabbitmq.com/tutorials/tutorial-six-ruby.html
- C#: http://www.rabbitmq.com/tutorials/tutorial-six-dotnet.html
- Javascript: http://www.rabbitmq.com/tutorials/tutorial-six-javascript.html
- Go: http://www.rabbitmq.com/tutorials/tutorial-six-go.html
- Elixir: http://www.rabbitmq.com/tutorials/tutorial-six-elixir.html

**Please focus on the part of rpc-server.**

## Copyright and License

Released under the [Mozilla Public License](http://www.rabbitmq.com/mpl.html),
the same as RabbitMQ.
