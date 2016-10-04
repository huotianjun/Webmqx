<?php
class Handler extends Thread {
	public function __construct(AMQPEnvelope $message)
	{
		$this->message = $message;
	}

	public function run(){
		//Establish connection to AMQP for rpc response.
		// attension: don't use $this->amqp_connection.
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
		// Your codes written in here.
		//

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
		$this->connection->setHost('127.0.0.1');
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

		// Exchange must set to  'webmqx'.
		$exchange_name = 'webmqx';

		// There can set many paths what you want to handle.
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

		// This callback to handle a webmqx http_rpc_request.
		$callback_func = function(AMQPEnvelope $message, AMQPQueue $q) {
			// A thread, a rpc request.
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
