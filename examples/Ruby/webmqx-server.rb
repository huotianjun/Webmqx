#!/usr/bin/env ruby
# encoding: utf-8

require "bunny"

# Connect to RabbitMQ server.
conn = Bunny.new("amqp://guest:guest@127.0.0.1", :automatically_recover => false)
conn.start

ch   = conn.create_channel

class WebmqxServer

  def initialize(ch)
    @ch = ch
  end

  def start()
    @x = @ch.exchange("webmqx", :type => "webmqx")
    @q = @ch.temporary_queue()
	@q.bind(@x, :routing_key => "/ruby-test/1")
	@q.bind(@x, :routing_key => "/ruby-test/1/2")
	@q.bind(@x, :routing_key => "/ruby-test/1/2/3")
	@q.bind(@x, :routing_key => "/ruby-test/3/2/1")

    @q.subscribe(:block => true) do |delivery_info, properties, payload|
      r = self.class.handle(payload)

      puts " [.] respose (#{r})"

      @x.publish(r, :routing_key => properties.reply_to, :correlation_id => properties.correlation_id)
    end
  end


  def self.handle(n)
	  "HelloWorld"
  end
end

begin
  server = WebmqxServer.new(ch)
  puts " [x] Awaiting HTTP requests"
  server.start()
rescue Interrupt => _
  ch.close
  conn.close
  exit(0)
end
