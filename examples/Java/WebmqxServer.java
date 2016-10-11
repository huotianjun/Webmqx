import com.rabbitmq.client.*;
import java.io.IOException;

public class WebmqxServer {
	public static void main(String[] argv) throws Exception {
		ConnectionFactory factory = new ConnectionFactory();
		factory.setUsername("guest");
		factory.setPassword("guest");
		factory.setHost("localhost");

		Connection connection = factory.newConnection();
		final Channel channel = connection.createChannel();

		String queueName = channel.queueDeclare().getQueue();
		channel.queueBind(queueName, "webmqx", "/Java/1");
		channel.queueBind(queueName, "webmqx", "/Java/1/2");
		channel.queueBind(queueName, "webmqx", "/Java/1/2/3");
		channel.queueBind(queueName, "webmqx", "/Java/3/2/1");

		channel.basicQos(1);

		System.out.println(" [x] Awaiting HTTP requests");

		Consumer consumer = new DefaultConsumer(channel) {
			@Override
			public void handleDelivery(String consumerTag, Envelope envelope, AMQP.BasicProperties properties, byte[] body)
			throws IOException {
				String message = new String(body, "UTF-8");
				System.out.println(" [x] Received '" + message + "'");
				BasicProperties replyProps = new BasicProperties.Builder().correlationId(properties.getCorrelationId()).build();
				
				//
				// Write your codes here
				//
				String response = "HelloWorld" ;
		
				channel.basicPublish( "", properties.getReplyTo(), replyProps, response.getBytes());
				channel.basicAck(envelope.getDeliveryTag(), false);
			};
		};

		channel.basicConsume(queueName, true, consumer);
	}
}
