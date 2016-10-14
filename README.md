Webmqx
======

- Webmqx is a HTTP server plugin for RabbitMQ server, and was built in a HTTP server of Cowboy. 

- Because it uses RabbitMQ client's pattern in your web services, so Webmqx client can easily be **embedded** in any other application server which can running anywhere, even in your home, and written in many language, such as Java/Python/Ruby/C#/Javascript/Go/etc. 

- Different from normal web server: with Webmqx, your application server 'pull' HTTP requests , to handle and response.

- It is easy to use: no parameterize with web server module of Webmqx,  and all HTTP requests routing to web service by the settings in your application.

- It can also be used as HTTP load-balancing proxy server.

- Webmqx is written in Erlang.

Enjoy it!

Goals
-----

Webmqx aims to Docker/microsevices. 

TO-DOs
------

- Other Webmqx examples of framework in web service by mainstream languages, /C#/Javascript/Go/Elixer/etc.

- Docker images for Webmqx client's frameworks.

- End-to-end monitor/trace/debug/test of web services.


Install Webmqx plugin
---------------------

 *  Install erlang/OTP.

 *  Install RabbitMQ server.

 *  Install Webmqx plugins:

The easiest	way	to utilize the Webmqx plugin is by installing the full codes available on Github.
```
$ git clone https://github.com/huotianjun/Webmqx.git
$ cd Webmqx
$ make dist
```
The plugin's files(*.ez) must be copy to plugins directory of the RabbitMQ distribution . 
To enable it:

```
$ ./rabbitmq-plugins enable Webmqx
```

Then, restart rabbitmq-server
```
$ ./rabbitmqctl stop
$ ./rabbitmq-server&
```
**If there are some errors for duplicate plugin files, remove the duplicated ones.**

Default HTTP port used by the plugin is `80`.

After all, test in shell: (XXX.XXX.XX.XX is RabbitMQ server's IP)
```
$ curl -i http://XXX.XXX.XX.XX/test/HelloWorld
```
If echo 'HelloWorld', it works.

How to use in web service
-------------------------

For example of Python 

```Python
#!/usr/bin/env python
import pika
import json

# If RabbitMQ server not running on localhost, you would use another user, but not 'guest'.
credentials = pika.PlainCredentials('guest', 'guest')
# Set RabbitMQ server's IP or host.
parameters =  pika.ConnectionParameters('localhost', credentials=credentials)
connection = pika.BlockingConnection(parameters)

channel = connection.channel()
queue = channel.queue_declare(exclusive=True, auto_delete=True).method.queue

# Exchange must be set to 'webmqx'.
# Your can bind many routing_keys(http paths), to 'pull' HTTP requests.
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py-test/1')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py-test/1/2')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py-test/1/2/3')
channel.queue_bind(exchange='webmqx', queue=queue, routing_key='/py-test/3/2/1')

def handle(http_path, http_qs, http_body):
    #
    # Write your codes, here, the entrance to your big application modules.
    #

    return 'HelloWorld' 

# Callback of basic_consume.
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

```

Startup the web service:
```
$ python webmqx-server.py&
```
**Atention: you can start it many times, and it also can be started on several hosts.** 

Test(On another terminal):
```
curl -i http://XXX.XXX.XX.XX/py-test/1/2/3
curl -i http://XXX.XXX.XX.XX/py-test/3/2/1
```
If echo 'HelloWorld', it works.


Other languages, reference to:

- C#: http://www.rabbitmq.com/tutorials/tutorial-six-dotnet.html
- Javascript: http://www.rabbitmq.com/tutorials/tutorial-six-javascript.html
- Go: http://www.rabbitmq.com/tutorials/tutorial-six-go.html
- Elixir: http://www.rabbitmq.com/tutorials/tutorial-six-elixir.html

**Please focus on the pattern of rpc-server.**

## Copyright and License

Released under the [Mozilla Public License](http://www.rabbitmq.com/mpl.html),
the same as RabbitMQ.
