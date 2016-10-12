#!/usr/bin/env ruby
# encoding: utf-8

require "bunny"
require "json"
require "pp"

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

		# Here, you can bind many routing_key(path of http), which you want 'pull' to handle.
		@q.bind(@x, :routing_key => "/ruby-test/1")
		@q.bind(@x, :routing_key => "/ruby-test/1/2")
		@q.bind(@x, :routing_key => "/ruby-test/1/2/3")
		@q.bind(@x, :routing_key => "/ruby-test/3/2/1")

		@q.subscribe(:block => true) do |delivery_info, properties, payload|
			rpc_body = JSON.parse(payload) 	
			http_req = rpc_body['req']
			http_body = rpc_body['body']
			http_host = http_req['host']
			http_method = http_req['method']
			http_path = http_req['path']
			http_qs = http_req['qs']

			puts " [.] http_body (#{http_body})"
			puts " [.] http_host (#{http_host})"
			puts " [.] http_method (#{http_method})"
			puts " [.] http_path (#{http_path})"
			puts " [.] http_qs (#{http_qs})"

			# Write your codes in function of handle()
			r = self.class.handle(http_host, http_method, http_path, http_qs, http_body)

			response_body = Hash["headers" => Hash["content-type" => "text/html"], "body" => r]

			puts " [.] respose (#{response_body.to_json})"

			response_ex = @ch.default_exchange
			response_ex.publish(response_body.to_json, :routing_key => properties.reply_to, :correlation_id => properties.correlation_id)
			#@ch.ack(delivery_info.delivery_tag)
		end
	end
	
	def self.handle(http_host, http_method, http_path, http_qs, http_body)

		#
		# Write your codes at here.
		#
		"HelloWorld"
	end
end

begin
	server = WebmqxServer.new(ch)
	puts " [x] Awaiting HTTP requests"
	server.start()
rescue Interrupt => _
	puts " [.] Exit (#{Interrupt})"
	ch.close
	conn.close
	exit(0)
end
