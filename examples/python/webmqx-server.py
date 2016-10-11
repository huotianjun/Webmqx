#!/usr/bin/env python
import pika
import json

# If not running on localhost of RabbitMQ server, don't use the user of 'guest', but try other. 
credentials = pika.PlainCredentials('guest', 'guest')
parameters =  pika.ConnectionParameters('localhost', credentials=credentials)
connection = pika.BlockingConnection(parameters)

channel = connection.channel()
queue = channel.queue_declare(exclusive=True, auto_delete=True).method.queue

# Exchange must be set to 'webmqx'.
# Your can bind many routing_key as http path.
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py/1')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py/1/2')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py/1/2/3')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py/3/2/1')

def handle(http_path, http_qs, http_body):
    #
    # Write your codes, here.
    #

    return 'HelloWorld' 

# TODO: run it at a thread.
def on_request(ch, method, props, body):
    rpc_request = json.loads(body)
    http_request = rpc_request['req']
    http_body = rpc_request['body']
    http_path = http_request['path']
    http_qs = http_request['qs']

    response = handle(http_path, http_qs, http_body)

    response_body = json.dumps({'headers': {'content-type': 'text/html'}, 'body': response}, sort_keys=True)

    ch.basic_publish(exchange='',
                        routing_key=props.reply_to,
                        properties=pika.BasicProperties(correlation_id = \
                            props.correlation_id),
                        body=str(response_body))
    ch.basic_ack(delivery_tag = method.delivery_tag)

channel.basic_qos(prefetch_count=1)
channel.basic_consume(on_request, queue=queue)

print(" [x] Awaiting HTTP requests")
try:
    channel.start_consuming()
finally:
    connection.close()
