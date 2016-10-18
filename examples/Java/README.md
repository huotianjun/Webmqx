Install Java AMQP Client Library 
--------------------------------

RabbitMQ speaks multiple protocols. This tutorial uses AMQP 0-9-1, which is an open, general-purpose protocol for messaging. There are a number of clients for RabbitMQ in many different languages. We'll use the Java client provided by RabbitMQ.

First, on your application server's host, download the client library package, and check its signature as described. Unzip it into your working directory and grab the JAR files from the unzipped directory:

```
$ cd exaples/Java
$ wget http://www.rabbitmq.com/releases/rabbitmq-java-client/v3.6.5/rabbitmq-java-client-bin-3.6.5.zip
$ unzip rabbitmq-java-client-bin-*.zip
$ cp rabbitmq-java-client-bin-*/*.jar ./
```

And, download the json library package:(we use JSON-java library: https://github.com/stleary/JSON-java , Downloadable jar: http://mvnrepository.com/artifact/org.json/json )

Test
----
On your applicatoin server's host, startup the test server:  
```
$ export CP=.:commons-io-1.2.jar:commons-cli-1.1.jar:rabbitmq-client.jar:JSON-java.jar
$ javac -cp $CP WebmqxServer.java
$ java -cp $CP WebqmxServer
```

And, on another terminal, type this:
```
$ curl -i XXX.XXX.XX.XX/java-test/1
$ curl -i XXX.XXX.XX.XX/java-test/1/2
$ curl -i XXX.XXX.XX.XX/java-test/1/2/3
$ curl -i XXX.XXX.XX.XX/java-test/3/2/1
```
(XXX.XXX.XX.XX is the RabbitMQ server's IP)

If echo 'HelloWorld', it works.
enjoy it!
