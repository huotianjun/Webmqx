import com.rabbitmq.client.*;
import org.json.*;
import java.io.IOException;

public class WebmqxServer {
	private static String handle(String message) {
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
		return "HelloWorld";
	}

	public static void main(String[] argv) throws Exception {
		Connection connection = null;
		Channel channel = null;
		try {
			ConnectionFactory factory = new ConnectionFactory();
			factory.setUsername("guest");
			factory.setPassword("guest");
			factory.setHost("localhost");

			connection = factory.newConnection();
			channel = connection.createChannel();

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
				String response = null;
				String response_string = null;
				QueueingConsumer.Delivery delivery = consumer.nextDelivery();
				        
				BasicProperties props = delivery.getProperties();
				BasicProperties replyProps = new BasicProperties.Builder().correlationId(props.getCorrelationId()).build();
				try {
					String message = new String(delivery.getBody(),"UTF-8");
					System.out.println(" [x] Received '" + message + "'");

					response = handle(message); 

					JSONObject response_body = new JSONObject();
					JSONObject headers_body = new JSONObject();
					headers_body.put("content-type", "text/html");
					response_body.put("headers", headers_body);
					response_body.put("body", response);

					response_string = response_body.toString();
					System.out.println(" response " + response_string );
				}
				catch (Exception e){
					System.out.println(" [.] " + e.toString());
					response = "";
				}
				finally {  
					channel.basicPublish("", props.getReplyTo(), replyProps, response_string.getBytes("UTF-8"));
					channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
				}
			}
		}
		catch  (Exception e) {
			e.printStackTrace();
		}
		finally {
			if (connection != null) {
				try {
					connection.close();
				}
				catch (Exception ignore) {}
				}
		}  
	}
}
