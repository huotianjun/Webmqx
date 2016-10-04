Webmqx
======

Webmqx is a HTTP server plugin for RabbitMQ , and it's HTTP server is based on Cowboy.

Webmqx is written in Erlang.
The power is RabbitMQ and Cowboy.

The plugin's files(*.ez) must be copy to plugins directory of the RabbitMQ distribution .  To enable
it, use <href="http://www.rabbitmq.com/man/rabbitmq-plugins.1.man.html">rabbitmq-plugins</a>:

	rabbitmq-plugins enable webmqx

Default HTTP port used by the plugin is `80`.

you must have Erlang/OTP .
The easiest	way	to utilize riak_kv is by installing the full Riak application available on Github.
Riak KV provides a key/value datastore and features MapReduce, lightweight data relations, and several different client APIs.
Embrace the power and simplicity of Makefiles.

Goals
-----

Cowboy aims to provide a **complete** HTTP stack in a **small** code base.
It is optimized for **low latency** and **low memory usage**, in part
because it uses **binary strings**.

Cowboy provides **routing** capabilities, selectively dispatching requests
to handlers written in Erlang.

Because it uses Ranch for managing connections, Cowboy can easily be
**embedded** in any other application.

No parameterized module. No process dictionary. **Clean** Erlang code.


Sponsors
--------

The project is currently sponsored by
[Sameroom](https://sameroom.io).

The original SPDY implementation was sponsored by
[LeoFS Cloud Storage](http://leo-project.net/leofs/).
It has since been superseded by HTTP/2.


Online documentation
--------------------

 *  [User guide](http://ninenines.eu/docs/en/cowboy/HEAD/guide)
 *  [Function reference](http://ninenines.eu/docs/en/cowboy/HEAD/manual)

Offline documentation
---------------------

 *  While still online, run `make docs`
 *  Function reference man pages available in `doc/man3/` and `doc/man7/`
 *  Run `make install-docs` to install man pages on your system
 *  Full documentation in Markdown available in `doc/markdown/`
 *  Examples available in `examples/`

Getting help
------------

 *  Official IRC Channel: #ninenines on irc.freenode.net
 *  [Mailing Lists](http://lists.ninenines.eu)
 *  [Commercial Support](http://ninenines.eu/support)

## Copyright and License

Released under the [Mozilla Public License](http://www.rabbitmq.com/mpl.html),
the same as RabbitMQ.
