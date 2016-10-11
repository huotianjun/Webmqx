import com.rabbitmq.client.AMQP.BasicProperties;
import com.rabbitmq.client.ConnectionFactory;
import com.rabbitmq.client.Connection;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.Consumer;
import com.rabbitmq.client.DefaultConsumer;

public class webmqx-server {
	public String handle(String message) throws Exception {

	}

	public static void main(String []args) {
		ConnectionFactory factory = new ConnectionFactory();
		factory.setUsername("guest");
		factory.setPassword("guest");
		factory.setHost("localhost");

		Connection connection = factory.newConnection();
		Channel channel = connection.createChannel();

		String queueName = channel.queueDeclare().getQueue();
		channel.queueBind(queueName, "webmqx", "/Java/1");
		channel.queueBind(queueName, "webmqx", "/Java/1/2");
		channel.queueBind(queueName, "webmqx", "/Java/1/2/3");
		channel.queueBind(queueName, "webmqx", "/Java/3/2/1");

		channel.basicQos(1);

		QueueingConsumer consumer = new QueueingConsumer(channel);
		channel.basicConsume(queueName, false, consumer);

		System.out.println(" [x] Awaiting HTTP requests");

		while (true) {
			QueueingConsumer.Delivery delivery = consumer.nextDelivery();

			BasicProperties props = delivery.getProperties();
			BasicProperties replyProps = new BasicProperties
												.Builder()
												.correlationId(props.getCorrelationId())
												.build();
			String message = new String(delivery.getBody());


			System.out.println(" [.] handle(" + message + ")");
			String response = "" + handle();
	
			channel.basicPublish( "", props.getReplyTo(), replyProps, response.getBytes());
			channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
		}
	}
}
