Install Java AMQP Client Library 
--------------------------------

RabbitMQ speaks multiple protocols. This tutorial uses AMQP 0-9-1, which is an open, general-purpose protocol for messaging. There are a number of clients for RabbitMQ in many different languages. We'll use the Java client provided by RabbitMQ.

Download the client library package, and check its signature as described. Unzip it into your working directory and grab the JAR files from the unzipped directory:
```
$ unzip rabbitmq-java-client-bin-*.zip
$ cp rabbitmq-java-client-bin-*/*.jar ./
```
(The RabbitMQ Java client is also in the central Maven repository, with the groupId com.rabbitmq and the artifactId amqp-client.)


```
$ javac -cp rabbitmq-client.jar webmqx-server.java
$ export CP=.:commons-io-1.2.jar:commons-cli-1.1.jar:rabbitmq-client.jar
$ java -cp $CP webqmx-server
```

git clone https://github.com/stleary/JSON-Java.git src/main/java/org/json
