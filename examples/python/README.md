Install pika
------------
Your Python's version >= 2.5.1 .

```
$ cd examples/Python
$ git clone https://github.com/pika/pika.git
$ cd pika
$ python setup.py install
```

Test
----

```
$ python webmqx-server.py
```

And, on other terminal:

```
$ curl -i XXX.XXX.XX.XX/py-test/1
$ curl -i XXX.XXX.XX.XX/py-test/1/2
$ curl -i XXX.XXX.XX.XX/py-test/1/2/3
$ curl -i XXX.XXX.XX.XX/py-test/3/2/1
```
('XXX.XXX.XX.XX' is the RabbitMQ server's IP.) 

If echo 'HelloWorld', it works.


