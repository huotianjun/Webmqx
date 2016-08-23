PROJECT = webmqx
PROJECT_DESCRIPTION = New project
PROJECT_VERSION = 0.0.1

DEPS = cowboy amqp_client jiffy
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

LOCAL_DEPS = ssl observer runtime_tools
dep_cowboy_commit = master

include rabbitmq-components.mk
include erlang.mk
