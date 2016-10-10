Install pika
------------

git clone https://github.com/pika/pika.git
cd pika
python setup.py install

Test
----

```
python webmqx-server.py
```

And, on other terminal:

'XXX.XXX.XX.XX' is the RabbitMQ server's IP. 
'''
curl -i XXX.XXX.XX.XX/py/1
curl -i XXX.XXX.XX.XX/py/1/2
curl -i XXX.XXX.XX.XX/py/1/2/3
curl -i XXX.XXX.XX.XX/py/3/2/1
'''



