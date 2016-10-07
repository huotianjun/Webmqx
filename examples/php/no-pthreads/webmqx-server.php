<?php
class WebmqxServer {

	private $connection;
	private $channel;
	private $queue;
	private $exchange;

	private function connect() {
		//Establish connection to AMQP
		$this->connection = new AMQPConnection();
		$this->connection->setHost('127.0.0.1');
		$this->connection->setLogin('guest');
		$this->connection->setPassword('guest');
		$this->connection->connect();

		//Declare Channel
		$this->channel = new AMQPChannel($this->connection);
		$this->channel->setPrefetchCount(1);

		$this->queue = new AMQPQueue($this->channel);
		$this->queue->setFlags(AMQP_EXCLUSIVE | AMQP_AUTODELETE);
		$this->queue->declareQueue();

		// Exchange must set to  'webmqx'. 
		$exchange_name = 'webmqx';

		// There can set many paths which you want to handle.
		$binding_key1 = '/1';
		$binding_key2 = '/1/2';
		$binding_key3 = '/1/2/3';
		$binding_key4 = '/3/2/1';

		$this->queue->bind($exchange_name, $binding_key1);
		$this->queue->bind($exchange_name, $binding_key2);
		$this->queue->bind($exchange_name, $binding_key3);
		$this->queue->bind($exchange_name, $binding_key4);

		$this->exchange = new AMQPExchange($this->channel);
	}

	public function init() {

		$this->connect();	

		$server = $this;
		$ex = $this->exchange;

		$callback_func = function(AMQPEnvelope $message, AMQPQueue $q) use ($ex, $server) {
			$rpc_request = json_decode($message->getBody(), true);
			$http_request = $rpc_request['req'];
			$http_body = $rpc_request['body'];
			$http_path = $http_request['path'];
			$http_query = $http_request['qs'];

			$attributes = array(
								'correlation_id' => $message->getCorrelationId()
								);

			$result = $server->handle($http_path, $http_query, $http_body);

			$ex->publish(	(string)($result),
									$message->getReplyTo(), 
									AMQP_NOPARAM,
									$attributes
								);
			
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

	public function handle($http_path, $http_query, $http_body) {

		//
		// Your codes would be written in here.
		//
		$response_body = 'Hello World';

		$response = array (
						'headers' => array ( 'content-type' => 'text/html') ,
						'body' => $response_body
					   );
		   
		return json_encode($response);
	}
}

$WebmqxServer = new WebmqxServer;
$WebmqxServer->init() or print 'no request data';

?>
