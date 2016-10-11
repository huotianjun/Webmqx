import com.rabbitmq.client.*;
import org.json.*;
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

				JSONObject rpc_request = new JSONObject(message);
				JSONObject http_req = rpc_request.getJSONObject("req");
				String http_host = http_req.getString("host");
				String http_method = http_req.getString("method");
				String http_path = http_req.getString("path");
				String http_qs = http_req.getString("qs");

				System.out.println(" req " +  http_req.toString());

				String http_body = rpc_request.getString("body");
				System.out.println(" body " + http_body );
				
				//
				// Write your codes here
				//
				String response = "HelloWorld" ;

				JSONObject response_body = new JSONObject();
				JSONObject headers_body = new JSONObject();
				headers_body.put("content-type", "text/html");
				response_body.put("headers", headers_body);
				response_body.put("body", response);

				String response_string = response_body.toString();
				System.out.println(" response " + response_string );
				
				AMQP.BasicProperties replyProps = new AMQP.BasicProperties.Builder().correlationId(properties.getCorrelationId()).build();
				channel.basicPublish( "", properties.getReplyTo(), replyProps, response_string.getBytes());
				channel.basicAck(envelope.getDeliveryTag(), false);
			};
		};

		while (true) {
			channel.basicConsume(queueName, true, consumer);
		}
		catch  (Exception e) {
			e.printStackTrace();
		}
	}
}
